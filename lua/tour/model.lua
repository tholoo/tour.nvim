local project = require("tour.project")
local M = {}

---@class tour.Position
---@field line integer 1-based line
---@field col integer 0-based byte offset
---@class tour.Range
---@field start tour.Position
---@field end tour.Position Exclusive end
---@class tour.Annotation
---@field range tour.Range
---@field placement 'above'|'below'|'inline'|'eol'|'highlight'
---@field text? string
---@class tour.Step
---@field id? string
---@field title string
---@field location {file: string, range: tour.Range, anchor?: string}
---@field description? string
---@field annotations? tour.Annotation[]
---@class tour.Data
---@field version integer
---@field id? string
---@field title string
---@field project_root? string
---@field created_at? string
---@field updated_at? string
---@field current_step? integer
---@field completed? boolean
---@field source? table<string, any>
---@field steps tour.Step[]

local function fail(path, message)
  error(path .. ": " .. message, 0)
end

local function object(value, path, keys)
  if type(value) ~= "table" or (vim.islist(value) and next(value) ~= nil) then
    fail(path, "must be an object")
  end
  for key in pairs(value) do
    if not keys[key] then
      fail(path, "unknown field " .. tostring(key))
    end
  end
end

local function fields(names)
  local result = {}
  for name in names:gmatch("%S+") do
    result[name] = true
  end
  return result
end

local function string_value(value, path, optional, empty)
  if value == nil and optional then
    return
  end
  if type(value) ~= "string" or (not empty and not value:find("%S")) then
    fail(path, "must be a non-empty string")
  end
  if value:find("%z") then
    fail(path, "must not contain NUL")
  end
end

local function integer(value, path, min)
  if type(value) ~= "number" or value ~= math.floor(value) or value == math.huge or value < min then
    fail(path, "must be an integer >= " .. min)
  end
end

local function range(value, path, capture)
  local check = capture or function(fn, ...)
    fn(...)
    return true
  end
  local valid = check(object, value, path, fields("start end"))
  if type(value) ~= "table" then
    return
  end
  for _, key in ipairs({ "start", "end" }) do
    local point = value[key]
    if point == nil then
      check(fail, path, "range is missing " .. key .. " position")
      valid = false
    else
      local object_ok = check(object, point, path .. "." .. key, fields("line col"))
      valid = object_ok and valid
      if type(point) == "table" then
        local line_ok = check(integer, point.line, path .. "." .. key .. ".line", 1)
        local col_ok = check(integer, point.col, path .. "." .. key .. ".col", 0)
        valid = line_ok and col_ok and valid
      end
    end
  end
  if valid then
    local a, b = value.start, value["end"]
    if b.line < a.line or (b.line == a.line and b.col < a.col) then
      check(fail, path, "end must not precede start")
    end
  end
end

local function list(value, path)
  if type(value) ~= "table" or not vim.islist(value) then
    fail(path, "must be an array")
  end
end

local function json_value(value, path, seen)
  if value == vim.NIL then
    return
  end
  local kind = type(value)
  if kind == "string" or kind == "boolean" then
    return
  end
  if kind == "number" and value == value and math.abs(value) ~= math.huge then
    return
  end
  if kind ~= "table" or seen[value] then
    fail(path, "must contain only acyclic JSON data")
  end
  seen[value] = true
  local array = vim.islist(value)
  for k, v in pairs(value) do
    if (array and type(k) ~= "number") or (not array and type(k) ~= "string") then
      fail(path, "invalid JSON key")
    end
    json_value(v, path, seen)
  end
  seen[value] = nil
end

function M.timestamp()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

-- Collect independent structural failures, skipping only malformed parent objects.
-- Rendering, source reads and persistence never participate in these checks.
function M.validate(input)
  local errors = {}
  local function check(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
      local message = tostring(err)
      errors[#errors + 1] = {
        code = "invalid_schema",
        path = message:match("^([^:]+):") or "tour",
        message = message,
      }
    end
    return ok
  end
  local function condition(ok, path, message)
    if not ok then
      check(fail, path, message)
    end
  end
  if
    not check(
      object,
      input,
      "tour",
      fields(
        "version id title project_root created_at updated_at current_step completed source steps"
      )
    )
  then
    -- Unknown fields do not prevent checking known fields of an object.
    if type(input) ~= "table" or vim.islist(input) then
      return errors
    end
  end
  condition(input.version == 1, "version", "must be 1")
  check(string_value, input.title, "title")
  for _, key in ipairs({ "id", "project_root", "created_at", "updated_at" }) do
    check(string_value, input[key], key, true)
  end
  if type(input.id) == "string" then
    condition(
      input.id:match("^[A-Za-z0-9_-]+$") and #input.id <= 128,
      "id",
      "must contain 1-128 ASCII letters, digits, underscores or hyphens"
    )
  end
  for _, key in ipairs({ "created_at", "updated_at" }) do
    if type(input[key]) == "string" then
      condition(
        input[key]:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$"),
        key,
        "must use UTC YYYY-MM-DDTHH:MM:SSZ"
      )
    end
  end
  condition(
    input.completed == nil or type(input.completed) == "boolean",
    "completed",
    "must be a boolean"
  )
  if input.source ~= nil then
    if type(input.source) ~= "table" or (vim.islist(input.source) and next(input.source)) then
      check(fail, "source", "must be an object")
    else
      check(json_value, input.source, "source", {})
    end
  end
  if not check(list, input.steps, "steps") then
    return errors
  end
  condition(#input.steps > 0, "steps", "must contain at least one step")
  if input.current_step ~= nil and check(integer, input.current_step, "current_step", 1) then
    condition(input.current_step <= #input.steps, "current_step", "exceeds step count")
  end
  local ids = {}
  for i, step in ipairs(input.steps) do
    local path = "step " .. i
    check(object, step, path, fields("id title location description annotations"))
    if type(step) == "table" then
      check(string_value, step.title, path .. ".title")
      check(string_value, step.id, path .. ".id", true)
      check(string_value, step.description, path .. ".description", true, true)
      if type(step.id) == "string" then
        condition(not ids[step.id], path .. ".id", "duplicate step id")
        ids[step.id] = true
      end
      check(object, step.location, path .. ".location", fields("file range anchor"))
      if type(step.location) == "table" then
        check(string_value, step.location.file, path .. ".location.file")
        check(string_value, step.location.anchor, path .. ".location.anchor", true)
        if type(step.location.anchor) == "string" then
          condition(
            not step.location.anchor:find("[\r\n]"),
            path .. ".location.anchor",
            "must be a single line"
          )
        end
        range(step.location.range, path .. ".location.range", check)
      end
      if step.annotations ~= nil and check(list, step.annotations, path .. ".annotations") then
        for j, note in ipairs(step.annotations) do
          local at = path .. " annotation " .. j
          check(object, note, at, fields("range text placement"))
          if type(note) == "table" then
            range(note.range, at .. ".range", check)
            condition(
              fields("above below inline eol highlight")[note.placement],
              at,
              "unknown placement " .. vim.inspect(note.placement)
            )
            check(string_value, note.text, at .. ".text", note.placement == "highlight")
          end
        end
      end
    end
  end
  return errors
end

-- Used by the authoring helper for its optional search scope.
function M.check_range(value)
  range(value, "range")
end

---@param input tour.Data
---@return tour.Data
function M.normalize(input)
  local errors = M.validate(input)
  if #errors > 0 then
    error(errors[1].message, 0)
  end
  local data = vim.deepcopy(input)
  data.id = data.id
    or (
      "tour-" .. vim.fn.sha256(tostring(vim.uv.hrtime()) .. tostring(vim.uv.os_getpid())):sub(1, 24)
    )
  data.project_root = project.root(data.project_root)
  data.current_step = data.current_step or 1
  data.completed = data.completed or false
  data.created_at = data.created_at or M.timestamp()
  data.updated_at = data.updated_at or data.created_at
  if data.source and next(data.source) == nil then
    data.source = vim.empty_dict()
  end
  for _, step in ipairs(data.steps) do
    step.location.file = project.relative(data.project_root, step.location.file)
    step.annotations = step.annotations or {}
  end
  return data
end

return M
