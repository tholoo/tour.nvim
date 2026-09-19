local model = require("tour.model")
local M = {}
local uv = vim.uv

function M.read(path)
  local fd, err = uv.fs_open(path, "r", 384)
  if not fd then
    error("cannot read " .. path .. ": " .. err, 0)
  end
  local ok, result = pcall(function()
    local stat = assert(uv.fs_fstat(fd))
    return vim.json.decode(assert(uv.fs_read(fd, stat.size, 0)))
  end)
  uv.fs_close(fd)
  if not ok then
    error("invalid JSON in " .. path .. ": " .. result, 0)
  end
  return result
end

-- Same-directory exclusive temporary file; fsync and close before atomic rename.
function M.atomic_write(path, data)
  local encoded = vim.json.encode(data)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local temporary = path .. ".tmp-" .. uv.os_getpid() .. "-" .. uv.hrtime()
  local fd = assert(uv.fs_open(temporary, "wx", 384))
  local ok, err = pcall(function()
    local offset = 0
    while offset < #encoded do
      local written = assert(uv.fs_write(fd, encoded:sub(offset + 1), offset))
      assert(written > 0, "short write")
      offset = offset + written
    end
    assert(uv.fs_fsync(fd))
    assert(uv.fs_close(fd))
    fd = nil
    assert(uv.fs_rename(temporary, path))
  end)
  if fd then
    uv.fs_close(fd)
  end
  if not ok then
    uv.fs_unlink(temporary)
    error("cannot save " .. path .. ": " .. err, 0)
  end
end

local function filename(base, id)
  if type(id) ~= "string" or not id:match("^[%w_-]+$") or #id > 128 then
    error("invalid tour id", 0)
  end
  return vim.fs.joinpath(base, "tours", id .. ".json")
end

local function index(base)
  local ok, result = pcall(M.read, vim.fs.joinpath(base, "index.json"))
  if
    ok
    and type(result) == "table"
    and result.version == 1
    and type(result.projects) == "table"
  then
    local projects = vim.empty_dict()
    for root, id in pairs(result.projects) do
      if
        type(root) == "string"
        and type(id) == "string"
        and id:match("^[A-Za-z0-9_-]+$")
        and #id <= 128
      then
        projects[root] = id
      end
    end
    return { version = 1, projects = projects }
  end
  return { version = 1, projects = vim.empty_dict() }
end

function M.save(base, data)
  local normalized = model.normalize(data)
  local path = filename(base, data.id)
  if uv.fs_stat(path) then
    local existing = M.read(path)
    if existing.project_root ~= data.project_root then
      error("tour id already belongs to another project: " .. data.id, 0)
    end
  end
  M.atomic_write(path, normalized)
  local idx = index(base)
  idx.projects[data.project_root] = data.id
  M.atomic_write(vim.fs.joinpath(base, "index.json"), idx)
end

function M.open(base, id)
  local data = model.normalize(M.read(filename(base, id)))
  if data.id ~= id then
    error("saved tour id does not match filename", 0)
  end
  return data
end

function M.list(base, root)
  local result = {}
  local dir = vim.fs.joinpath(base, "tours")
  if not uv.fs_stat(dir) then
    return result
  end
  for name, kind in vim.fs.dir(dir) do
    if kind == "file" and name:match("%.json$") then
      local ok, data = pcall(M.open, base, name:sub(1, -6))
      if ok and (not root or data.project_root == root) then
        result[#result + 1] = data
      elseif not ok then
        vim.notify("tour.nvim: skipping " .. name .. ": " .. data, vim.log.levels.WARN)
      end
    end
  end
  table.sort(result, function(a, b)
    if a.updated_at == b.updated_at then
      return a.id < b.id
    end
    return a.updated_at > b.updated_at
  end)
  return result
end

function M.recent(base, root)
  local id = index(base).projects[root]
  if id then
    local ok, data = pcall(M.open, base, id)
    if ok and data.project_root == root then
      return data
    end
  end
  return M.list(base, root)[1]
end

return M
