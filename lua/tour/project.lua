local M = {}

function M.canonical(path)
  path = vim.fs.normalize(vim.fs.abspath(path))
  local real = vim.uv.fs_realpath(path)
  if real then
    return real
  end
  local parent = vim.fs.dirname(path)
  if parent and parent ~= path then
    return vim.fs.joinpath(M.canonical(parent), vim.fs.basename(path))
  end
  return path
end

function M.root(explicit)
  if explicit then
    return M.canonical(explicit)
  end
  local cwd = M.canonical(vim.fn.getcwd())
  return M.canonical(vim.fs.root(cwd, ".git") or cwd)
end

function M.absolute(root, file)
  return M.canonical(file:sub(1, 1) == "/" and file or vim.fs.joinpath(root, file))
end

function M.relative(root, file)
  local absolute = M.absolute(root, file)
  local prefix = root == "/" and root or root .. "/"
  return absolute:sub(1, #prefix) == prefix and absolute:sub(#prefix + 1) or absolute
end

return M
