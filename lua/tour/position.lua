local M = {}

-- All public line <-> API row conversion lives here. Ends are exclusive.
function M.row(line)
  return line - 1
end

function M.point(row, col)
  return { line = row + 1, col = col }
end

function M.extmark(range)
  return M.row(range.start.line),
    range.start.col,
    {
      end_row = M.row(range["end"].line),
      end_col = range["end"].col,
      right_gravity = true,
      end_right_gravity = false,
      undo_restore = true,
    }
end

function M.valid(range, lines)
  for _, p in ipairs({ range.start, range["end"] }) do
    local line = lines[p.line]
    if not line or p.col > #line then
      return false
    end
    -- A byte offset must be a UTF-8 boundary, not inside a multibyte character.
    local byte = line:byte(p.col + 1)
    if byte and byte >= 128 and byte < 192 then
      return false
    end
  end
  return true
end

-- Convert literal-match byte offsets in newline-joined source centrally.
function M.from_offset(lines, offset)
  for row, line in ipairs(lines) do
    if offset <= #line then
      return { line = row, col = offset }
    end
    offset = offset - #line - 1
  end
  error("source offset is out of bounds", 0)
end

function M.offset(lines, point)
  local offset = point.col
  for line = 1, M.row(point.line) do
    offset = offset + #lines[line] + 1
  end
  return offset
end

function M.shift(range, delta)
  range.start.line = range.start.line + delta
  range["end"].line = range["end"].line + delta
end

function M.last_line(range)
  if range["end"].col == 0 and range["end"].line > range.start.line then
    return range["end"].line - 1
  end
  return range["end"].line
end

return M
