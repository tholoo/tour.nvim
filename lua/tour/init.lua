---@class tour.API
---@field start fun(data: tour.Data): tour.Data
---@field load fun(path: string): tour.Data
---@field read_source fun(file: string, opts?: {project_root?: string}): tour.Source|table
---@field resolve fun(opts: {file: string, snippet: string, project_root?: string, within?: tour.Range, revision?: string}): table
---@field validate fun(data: tour.Data, opts?: {revisions?: table<string, string>}): tour.Validation
---@field start_checked fun(data: tour.Data, opts?: {revisions?: table<string, string>}): tour.Receipt
---@field load_checked fun(path: string, opts?: {revisions?: table<string, string>}): tour.Receipt
---@field resume fun(): tour.Data
---@field open fun(id: string): tour.Data
---@field next fun(): tour.Data
---@field prev fun(): tour.Data
---@field goto_step fun(index: integer): tour.Data
---@field overview fun()
---@field list fun(opts?: {all?: boolean}): tour.Data[]
---@field save fun(): tour.Data
---@field close fun()
---@field finish fun()
---@field restart fun(): tour.Data
---@field current fun(): tour.Data?
---@field statusline fun(): string
---@field gutter fun(): string
---@type tour.API
local M = {}
local ready = false

---@param opts? {storage?: {path?: string, autosave?: boolean}, render?: {max_width?: integer}, mappings?: table<string, string>}
function M.setup(opts)
  require("tour.session").setup(opts)
  require("tour.commands").setup()
  ready = true
end

-- Cheap, side-effect-free statuscolumn segment, including for custom gutters.
function M.gutter()
  return require("tour.render.gutter").text()
end

-- Authoring reads must not initialize UI, autocmds, storage, or a session.
for _, name in ipairs({ "read_source", "resolve", "validate" }) do
  M[name] = function(...)
    return require("tour.author")[name](...)
  end
end

-- Public operations own no mutable state; session owns semantic and runtime state.
for _, name in ipairs({
  "start",
  "start_checked",
  "load_checked",
  "resume",
  "open",
  "next",
  "prev",
  "goto_step",
  "overview",
  "list",
  "save",
  "close",
  "finish",
  "restart",
  "current",
  "load",
  "statusline",
}) do
  M[name] = function(...)
    if not ready then
      M.setup()
    end
    return require("tour.session")[name](...)
  end
end

return M
