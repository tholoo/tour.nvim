local M = {}

function M.send(request, policy, transport)
  local attempts = 0
  repeat
    attempts = attempts + 1
    local result = transport.send_once(request)
    if result.ok or not policy.should_retry(result, attempts) then
      return result
    end
    transport.sleep(policy.delay(attempts))
  until attempts >= policy.limit
  return { ok = false, reason = "retry limit" }
end

return M
