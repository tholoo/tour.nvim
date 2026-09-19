local M = {}

-- Wrap by display cells, preserving paragraphs and explicit line breaks.
-- Break long words at character boundaries, never through UTF-8 bytes.
function M.wrap(text, width)
  width = math.max(1, math.floor(width))
  local output = {}
  for _, source in ipairs(vim.split(text, "\n", { plain = true })) do
    local line = ""
    local function emit()
      output[#output + 1] = line
      line = ""
    end
    for word in source:gmatch("%S+") do
      if line ~= "" and vim.fn.strdisplaywidth(line .. " " .. word) <= width then
        line = line .. " " .. word
      else
        if line ~= "" then
          emit()
        end
        for _, char in ipairs(vim.fn.split(word, "\\zs")) do
          if line ~= "" and vim.fn.strdisplaywidth(line .. char) > width then
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

function M.lines(text, width, prefix, group)
  local result = {}
  for _, line in ipairs(M.wrap(text, width - vim.fn.strdisplaywidth(prefix))) do
    result[#result + 1] = { { prefix .. line, group } }
  end
  return result
end

return M
