local M = {}

function M.make(opts)
  opts = opts or {}
  local config = vim.tbl_deep_extend("force", {
    storage = { path = vim.fn.stdpath("state") .. "/tour.nvim", autosave = true },
    render = { max_width = 88 },
    mappings = {},
  }, opts)
  assert(
    type(config.storage.path) == "string" and config.storage.path ~= "",
    "storage.path must be a path"
  )
  assert(type(config.storage.autosave) == "boolean", "storage.autosave must be a boolean")
  assert(
    type(config.render.max_width) == "number"
      and config.render.max_width >= 12
      and config.render.max_width == math.floor(config.render.max_width),
    "render.max_width must be an integer >= 12"
  )
  config.storage.path = require("tour.project").canonical(config.storage.path)
  return config
end

return M
