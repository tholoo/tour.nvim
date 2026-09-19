local M = {}

-- Counters are already part of headers and overview rows. Keep semantic titles
-- intact and suppress only a matching leading step number in presentation.
function M.step_title(title, index)
  return (title:gsub("^%s*" .. index .. "[.)]%s+", "", 1))
end

-- Wrap by display cells, preserving paragraphs and explicit line breaks.
-- Break long words at character boundaries, never through UTF-8 bytes.
function M.wrap(text, width, first_width)
  width = math.max(1, math.floor(width))
  local output = {}
  local function limit()
    return #output == 0 and first_width and math.max(1, first_width) or width
  end
  for _, source in ipairs(vim.split(text, "\n", { plain = true })) do
    local line = ""
    local function emit()
      output[#output + 1] = line
      line = ""
    end
    for word in source:gmatch("%S+") do
      if line ~= "" and vim.fn.strdisplaywidth(line .. " " .. word) <= limit() then
        line = line .. " " .. word
      else
        if line ~= "" then
          emit()
        end
        for _, char in ipairs(vim.fn.split(word, "\\zs")) do
          if line ~= "" and vim.fn.strdisplaywidth(line .. char) > limit() then
            emit()
          end
          line = line .. char
        end
      end
    end
    emit()
  end
  return output
end

function M.lines(text, width, prefix, group, continuation)
  local result = {}
  continuation = continuation or prefix
  local available = width
    - math.max(vim.fn.strdisplaywidth(prefix), vim.fn.strdisplaywidth(continuation))
  for i, line in ipairs(M.wrap(text, available)) do
    result[#result + 1] = { { (i == 1 and prefix or continuation) .. line, group } }
  end
  return result
end

return M
