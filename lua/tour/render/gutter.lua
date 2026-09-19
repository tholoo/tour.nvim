local api = vim.api
local position = require("tour.position")
local M = {}
local target

-- Native items retain Neovim's sign slots, folds and number/relativenumber
-- behavior. The tour owns only the extra cell to their right.
local format = "%C%s%=%l%#TourRange#%{v:lua.require'tour'.gutter()}%* "

function M.text()
  if not target or vim.v.virtnum < 0 or api.nvim_get_current_buf() ~= target.buf then
    return " "
  end
  local range = target.range
  if vim.v.lnum >= range.start.line and vim.v.lnum <= position.last_line(range) then
    return "▎"
  end
  return " "
end

function M.update(buf, range)
  target = buf and { buf = buf, range = range } or nil
  for _, win in ipairs(api.nvim_list_wins()) do
    local current = vim.wo[win].statuscolumn
    local relevant = target
      and api.nvim_win_get_buf(win) == buf
      and api.nvim_win_get_config(win).relative == ""
    if current == format and not relevant then
      vim.wo[win].statuscolumn = ""
    elseif relevant and current == "" then
      vim.wo[win].statuscolumn = format
    end
    -- A user's custom/replaced statuscolumn is never rewritten. They can
    -- include tour.gutter() in their own format to use the same indicator.
  end
  api.nvim__redraw({ statuscolumn = true })
end

function M.clear()
  M.update(nil)
end

return M
