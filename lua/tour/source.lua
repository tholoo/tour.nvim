-- Read source without creating buffers, firing read autocmds, or touching windows.
local project = require("tour.project")
local M = {}

---@class tour.Source
---@field file string Canonical absolute path
---@field lines string[] Raw lines, including unsaved edits when loaded
---@field revision string Content digest; transient, not persisted in tours
---@field origin 'buffer'|'disk'
---@field bufnr? integer Present only for a loaded buffer
---@field changedtick? integer Present only for a loaded buffer
---@field modified? boolean Present only for a loaded buffer

---@return tour.Source? source
---@return table? error
function M.read(root, file)
  file = project.absolute(root, file)
  local source = { file = file, origin = "disk" }
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" and vim.api.nvim_buf_is_loaded(buf) and project.canonical(name) == file then
      source.origin = "buffer"
      source.bufnr = buf
      source.changedtick = vim.api.nvim_buf_get_changedtick(buf)
      source.modified = vim.bo[buf].modified
      source.lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true)
      break
    end
  end
  if not source.lines then
    local stat = vim.uv.fs_stat(file)
    local handle = stat and stat.type == "file" and io.open(file, "rb")
    if not handle then
      return nil,
        {
          code = "unreadable_file",
          file = file,
          message = "target file is missing or unreadable: " .. file,
        }
    end
    local content, err = handle:read("*a")
    handle:close()
    if not content then
      return nil, { code = "unreadable_file", file = file, message = tostring(err) }
    end
    -- Source interchange is UTF-8; normalize BOM and DOS line endings as Nvim does.
    content = content:gsub("^\239\187\191", ""):gsub("\r\n", "\n")
    source.lines = vim.split(content, "\n", { plain = true })
    if #source.lines > 1 and source.lines[#source.lines] == "" then
      table.remove(source.lines)
    end
  end
  for _, line in ipairs(source.lines) do
    if line:find("%z") then
      return nil,
        {
          code = "unsupported_source",
          file = file,
          message = "source contains NUL bytes; expected UTF-8 text: " .. file,
        }
    end
  end
  source.revision = vim.fn.sha256(vim.json.encode(source.lines))
  return source
end

return M
