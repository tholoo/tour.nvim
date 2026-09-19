local position = require("tour.position")
local project = require("tour.project")
local M = {}

function M.resolve(root, original)
  local step = vim.deepcopy(original)
  local file = project.absolute(root, step.location.file)
  local existing = vim.fn.bufnr(file)
  if not (existing >= 0 and vim.api.nvim_buf_is_loaded(existing)) then
    local stat = vim.uv.fs_stat(file)
    if not stat or stat.type ~= "file" then
      error("target file is missing or unreadable: " .. file, 0)
    end
    if vim.fn.filereadable(file) ~= 1 then
      error("target file is unreadable: " .. file, 0)
    end
  end
  local buf = vim.fn.bufadd(file)
  vim.fn.bufload(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local location = step.location
  local nearest
  if location.anchor then
    for line, text in ipairs(lines) do
      if text:find(location.anchor, 1, true) then
        if
          not nearest
          or math.abs(line - location.range.start.line)
            < math.abs(nearest - location.range.start.line)
        then
          nearest = line
        end
      end
    end
  end
  if nearest then
    local delta = nearest - location.range.start.line
    position.shift(location.range, delta)
    for _, note in ipairs(step.annotations) do
      position.shift(note.range, delta)
    end
  end
  if not position.valid(location.range, lines) then
    error("cannot resolve range in " .. file .. "; update its range or anchor", 0)
  end
  for i, note in ipairs(step.annotations) do
    if not position.valid(note.range, lines) then
      error("annotation " .. i .. " has an invalid range in " .. file, 0)
    end
  end
  if not location.anchor then
    local anchor = vim.trim(lines[location.range.start.line])
    if #anchor > 0 then
      location.anchor = anchor
    end
  end
  return buf, step
end

return M
