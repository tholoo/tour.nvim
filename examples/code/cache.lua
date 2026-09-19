local M = {}

function M.read(key, cache, refresh)
  local entry = cache[key]
  if not entry then
    return refresh(key)
  end
  if entry.stale then
    vim.schedule(function()
      cache[key] = refresh(key)
    end)
  end
  return entry.value
end

return M
