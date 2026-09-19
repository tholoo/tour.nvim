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

local function range(value, path)
  object(value, path, fields("start end"))
  for _, key in ipairs({ "start", "end" }) do
    if value[key] == nil then
      fail(path, "range is missing " .. key .. " position")
    end
    object(value[key], path .. "." .. key, fields("line col"))
    integer(value[key].line, path .. "." .. key .. ".line", 1)
    integer(value[key].col, path .. "." .. key .. ".col", 0)
  end
  local a, b = value.start, value["end"]
  if b.line < a.line or (b.line == a.line and b.col < a.col) then
    fail(path, "end must not precede start")
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

---@param input tour.Data
---@return tour.Data
function M.normalize(input)
  object(
    input,
    "tour",
    fields(
      "version id title project_root created_at updated_at current_step completed source steps"
    )
  )
  if input.version ~= 1 then
    fail("version", "must be 1")
  end
  string_value(input.title, "title")
  for _, key in ipairs({ "id", "project_root", "created_at", "updated_at" }) do
    string_value(input[key], key, true)
  end
  if input.id and (not input.id:match("^[%w_-]+$") or #input.id > 128) then
    fail("id", "must contain 1-128 ASCII letters, digits, underscores or hyphens")
  end
  for _, key in ipairs({ "created_at", "updated_at" }) do
    if input[key] and not input[key]:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$") then
      fail(key, "must use UTC YYYY-MM-DDTHH:MM:SSZ")
    end
  end
  if input.completed ~= nil and type(input.completed) ~= "boolean" then
    fail("completed", "must be a boolean")
  end
  if input.source ~= nil then
    if type(input.source) ~= "table" or (vim.islist(input.source) and next(input.source)) then
      fail("source", "must be an object")
    end
    json_value(input.source, "source", {})
  end
  list(input.steps, "steps")
  if #input.steps == 0 then
    fail("steps", "must contain at least one step")
  end
  if input.current_step ~= nil then
    integer(input.current_step, "current_step", 1)
    if input.current_step > #input.steps then
      fail("current_step", "exceeds step count")
    end
  end
  local ids = {}
  for i, step in ipairs(input.steps) do
    local path = "step " .. i
    object(step, path, fields("id title location description annotations"))
    string_value(step.title, path .. ".title")
    string_value(step.id, path .. ".id", true)
    string_value(step.description, path .. ".description", true, true)
    if step.id then
      if ids[step.id] then
        fail(path .. ".id", "duplicate step id")
      end
      ids[step.id] = true
    end
    object(step.location, path .. ".location", fields("file range anchor"))
    string_value(step.location.file, path .. ".location.file")
    string_value(step.location.anchor, path .. ".location.anchor", true)
    if step.location.anchor and step.location.anchor:find("[\r\n]") then
      fail(path .. ".location.anchor", "must be a single line")
    end
    range(step.location.range, path .. ".location.range")
    if step.annotations ~= nil then
      list(step.annotations, path .. ".annotations")
      for j, note in ipairs(step.annotations) do
        local at = path .. " annotation " .. j
        object(note, at, fields("range text placement"))
        range(note.range, at .. ".range")
        if not fields("above below inline eol highlight")[note.placement] then
          fail(at, "unknown placement " .. vim.inspect(note.placement))
        end
        string_value(note.text, at .. ".text", note.placement == "highlight")
      end
    end
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
