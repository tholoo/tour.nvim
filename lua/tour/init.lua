---@class tour.API
---@field start fun(data: tour.Data): tour.Data
---@field load fun(path: string): tour.Data
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
---@type tour.API
local M = {}
local ready = false

---@param opts? {storage?: {path?: string, autosave?: boolean}, render?: {max_width?: integer}, mappings?: table<string, string>}
function M.setup(opts)
  require("tour.session").setup(opts)
  require("tour.commands").setup()
  ready = true
end

-- Public operations own no mutable state; session owns semantic and runtime state.
for _, name in ipairs({
  "start",
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
