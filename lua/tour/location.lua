local position = require("tour.position")
local project = require("tour.project")
local M = {}

-- Pure relocation shared by navigation and non-mutating whole-tour validation.
function M.relocate(original, lines)
  local step = vim.deepcopy(original)
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
  if not location.anchor and position.valid(location.range, lines) then
    local anchor = vim.trim(lines[location.range.start.line])
    if #anchor > 0 then
      location.anchor = anchor
    end
  end
  return step
end

function M.resolve(root, original)
  local file = project.absolute(root, original.location.file)
  local snapshot, err = require("tour.source").read(root, file)
  if not snapshot then
    error(err.message, 0)
  end
  local buf = snapshot.bufnr or vim.fn.bufadd(file)
  vim.fn.bufload(buf)
  -- Read again after BufRead autocmds and file decoding have run.
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true)
  local step = M.relocate(original, lines)
  if not position.valid(step.location.range, lines) then
    error("cannot resolve range in " .. file .. "; update its range or anchor", 0)
  end
  for i, note in ipairs(step.annotations) do
    if not position.valid(note.range, lines) then
      error("annotation " .. i .. " has an invalid range in " .. file, 0)
    end
  end
  return buf, step
end

return M
