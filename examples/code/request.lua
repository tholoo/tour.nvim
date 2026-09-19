local M = {}

local function route(request)
  if request.path == "/health" then
    return { status = 200, body = "ok" }
  end
  return { status = 404, body = "not found" }
end

function M.handle(request, database)
  local response = route(request)
  database:record(request.path, response.status)
  return response
end

return M
