local model = require("tour.model")
local project = require("tour.project")
local source = require("tour.source")
local position = require("tour.position")
local location = require("tour.location")
local M = {}

---@class tour.Problem
---@field code string Stable category
---@field message string Human-readable explanation
---@field path? string Field path
---@field file? string Canonical absolute source path
---@field step? integer 1-based step index
---@field annotation? integer 1-based annotation index
---@field range? tour.Range Rejected range, after anchor relocation
---@field bounds? table Valid line/byte bounds for the rejected endpoint

---@class tour.Validation
---@field ok boolean
---@field errors tour.Problem[]
---@field revisions? table<string, string> Canonical source path to content digest
---@field data? tour.Data Present only on success

---@class tour.Receipt
---@field ok boolean
---@field persisted boolean|userdata vim.NIL means a write was attempted but unconfirmed
---@field displayed boolean
---@field errors tour.Problem[]
---@field id? string
---@field title? string
---@field current_step? integer
---@field step_count? integer

local function failure(code, message)
  return { ok = false, errors = { { code = code, message = message } } }
end

local function path_string(value)
  return type(value) == "string" and value:find("%S") and not value:find("%z")
end

local function options(opts)
  return type(opts) == "table" and (opts.project_root == nil or path_string(opts.project_root))
end

function M.read_source(file, opts)
  opts = opts or {}
  if not path_string(file) or not options(opts) then
    return failure("invalid_request", "file and optional project_root must be non-empty paths")
  end
  local snapshot, err = source.read(project.root(opts.project_root), file)
  if not snapshot then
    return { ok = false, errors = { err } }
  end
  snapshot.ok = true
  return snapshot
end

local function range_errors(range, lines, context, errors)
  for _, endpoint in ipairs({ "start", "end" }) do
    local point = range[endpoint]
    local line = lines[point.line]
    local byte = line and line:byte(point.col + 1)
    local message
    if not line then
      message = "line must be between 1 and " .. #lines
    elseif point.col > #line then
      message = "byte column must be between 0 and " .. #line
    elseif byte and byte >= 128 and byte < 192 then
      message = "byte column is inside a UTF-8 character"
    end
    if message then
      local err = vim.deepcopy(context)
      err.code = "invalid_range"
      err.path = err.path .. "." .. endpoint
      err.message = err.path .. ": " .. message
      err.range = vim.deepcopy(range)
      err.bounds = { min_line = 1, max_line = #lines, min_col = 0, max_col = line and #line or nil }
      errors[#errors + 1] = err
    end
  end
end

---@param opts {file: string, snippet: string, project_root?: string, within?: tour.Range, revision?: string}
---@return table result Contains range and revision on success; candidates on ambiguity.
function M.resolve(opts)
  if
    not options(opts)
    or not path_string(opts.file)
    or type(opts.snippet) ~= "string"
    or opts.snippet == ""
    or opts.snippet:find("%z")
  then
    return failure("invalid_request", "resolve requires file and a non-empty literal snippet")
  end
  local snapshot = M.read_source(opts.file, opts)
  if not snapshot.ok then
    return snapshot
  end
  if opts.revision ~= nil and opts.revision ~= snapshot.revision then
    return {
      ok = false,
      errors = {
        {
          code = "stale_source",
          file = snapshot.file,
          expected_revision = opts.revision,
          actual_revision = snapshot.revision,
          message = "source changed since inspection; read it again before resolving",
        },
      },
    }
  end
  local lines = snapshot.lines
  local first, last = 0, #table.concat(lines, "\n")
  if opts.within ~= nil then
    local ok, err = pcall(model.check_range, opts.within)
    if not ok then
      return failure("invalid_schema", tostring(err))
    end
    local errors = {}
    range_errors(opts.within, lines, { path = "within", file = snapshot.file }, errors)
    if #errors > 0 then
      return { ok = false, errors = errors }
    end
    first, last =
      position.offset(lines, opts.within.start), position.offset(lines, opts.within["end"])
  end
  local haystack = table.concat(lines, "\n")
  local matches, offset = {}, first + 1
  while true do
    local a, b = haystack:find(opts.snippet, offset, true)
    if not a or b > last then
      break
    end
    local range =
      { start = position.from_offset(lines, a - 1), ["end"] = position.from_offset(lines, b) }
    if position.valid(range, lines) then
      matches[#matches + 1] = range
    end
    offset = a + 1 -- Include overlapping occurrences; never choose silently.
  end
  if #matches ~= 1 then
    return {
      ok = false,
      file = snapshot.file,
      revision = snapshot.revision,
      candidates = matches,
      errors = {
        {
          code = #matches == 0 and "snippet_not_found" or "ambiguous_snippet",
          file = snapshot.file,
          message = #matches == 0 and "literal snippet was not found"
            or ("literal snippet has %d matches; narrow within or use more context"):format(
              #matches
            ),
        },
      },
    }
  end
  return { ok = true, file = snapshot.file, range = matches[1], revision = snapshot.revision }
end

---@param input tour.Data
---@param opts? {revisions?: table<string, string>}
---@return tour.Validation result Normalized, relocated data only when ok.
function M.validate(input, opts)
  opts = opts or {}
  if type(opts) ~= "table" or (opts.revisions ~= nil and type(opts.revisions) ~= "table") then
    return failure("invalid_request", "revisions must map source paths to content revisions")
  end
  local errors = model.validate(input)
  local result = { ok = false, errors = errors, revisions = vim.empty_dict() }
  if
    type(input) ~= "table"
    or type(input.steps) ~= "table"
    or not vim.islist(input.steps)
    or (input.project_root ~= nil and not path_string(input.project_root))
  then
    return result
  end
  local root = project.root(input.project_root)
  for _, err in ipairs(errors) do
    err.step = tonumber(err.path:match("^step (%d+)"))
    err.annotation = tonumber(err.path:match("annotation (%d+)"))
    local step = err.step and input.steps[err.step]
    if
      type(step) == "table"
      and type(step.location) == "table"
      and path_string(step.location.file)
    then
      err.file = project.absolute(root, step.location.file)
    end
  end
  local normalized = #errors == 0 and model.normalize(input) or nil
  local cache = {}
  local function read(file)
    file = project.absolute(root, file)
    if not cache[file] then
      local snapshot, err = source.read(root, file)
      cache[file] = { snapshot = snapshot, error = err }
      if snapshot then
        result.revisions[file] = snapshot.revision
      end
    end
    return cache[file].snapshot, cache[file].error
  end
  -- Expected revisions can include additional inspected files, not just tour stops.
  for file, revision in pairs(opts.revisions or {}) do
    if not path_string(file) or type(revision) ~= "string" then
      errors[#errors + 1] =
        { code = "invalid_request", message = "revisions must map paths to strings" }
    else
      local snapshot, err = read(file)
      if not snapshot then
        errors[#errors + 1] = vim.deepcopy(err)
      elseif snapshot.revision ~= revision then
        errors[#errors + 1] = {
          code = "stale_source",
          file = snapshot.file,
          expected_revision = revision,
          actual_revision = snapshot.revision,
          message = "source changed since inspection; read it again before loading",
        }
      end
    end
  end
  for i, step in ipairs(input.steps) do
    if
      type(step) == "table"
      and type(step.location) == "table"
      and path_string(step.location.file)
    then
      local snapshot, err = read(step.location.file)
      if not snapshot then
        err = vim.deepcopy(err)
        err.step, err.path = i, "step " .. i .. ".location.file"
        errors[#errors + 1] = err
      else
        -- Keep checking valid ranges even when titles or neighboring annotations are malformed.
        local candidate = { location = vim.deepcopy(step.location), annotations = {} }
        local indices = {}
        if type(step.annotations) == "table" and vim.islist(step.annotations) then
          for j, note in ipairs(step.annotations) do
            if type(note) == "table" and pcall(model.check_range, note.range) then
              candidate.annotations[#candidate.annotations + 1] = vim.deepcopy(note)
              indices[#indices + 1] = j
            end
          end
        end
        local valid_primary = pcall(model.check_range, candidate.location.range)
        if valid_primary then
          if not path_string(candidate.location.anchor) then
            candidate.location.anchor = nil
          end
          candidate = location.relocate(candidate, snapshot.lines)
          range_errors(
            candidate.location.range,
            snapshot.lines,
            { step = i, file = snapshot.file, path = "step " .. i .. ".location.range" },
            errors
          )
        end
        for j, note in ipairs(candidate.annotations) do
          range_errors(note.range, snapshot.lines, {
            step = i,
            annotation = indices[j],
            file = snapshot.file,
            path = ("step %d annotation %d.range"):format(i, indices[j]),
          }, errors)
        end
        if normalized then
          normalized.steps[i].location = candidate.location
          normalized.steps[i].location.file = project.relative(root, snapshot.file)
          normalized.steps[i].annotations = candidate.annotations
        end
      end
    end
  end
  result.ok = #errors == 0
  if result.ok then
    result.data = normalized
  end
  return result
end

return M
