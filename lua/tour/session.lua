local model = require("tour.model")
local storage = require("tour.storage")
local project = require("tour.project")
local location = require("tour.location")
local render = require("tour.render")
local M = {}
local config = require("tour.config").make()
local active, runtime
local showing = false

local function require_active()
  assert(active, "no tour is loaded")
end

local function reconcile()
  if active then
    render.reconcile(runtime, active.steps[active.current_step])
  end
end

function M.save()
  require_active()
  reconcile()
  active.updated_at = model.timestamp()
  storage.save(config.storage.path, active)
  return vim.deepcopy(active)
end

local function autosave()
  if config.storage.autosave then
    M.save()
  end
end

local function reveal(data, index)
  -- Resolve on a copy before changing progress or removing the old UI.
  local buf, step = location.resolve(data.project_root, data.steps[index])
  -- nvim_set_current_buf preserves window layout and respects 'hidden'.
  vim.api.nvim_set_current_buf(buf)
  render.clear(runtime)
  runtime = nil
  data.steps[index] = step
  data.current_step = index
  active = data
  showing = true
  vim.api.nvim_win_set_cursor(0, { step.location.range.start.line, step.location.range.start.col })
  vim.api.nvim_cmd({ cmd = "normal", args = { "zv" }, bang = true }, {})
  runtime = render.attach(buf, step)
  render.draw(runtime, data, config.render)
  -- Center the region so virtual lines above it are visible when possible.
  vim.api.nvim_cmd({ cmd = "normal", args = { "zz" }, bang = true }, {})
end

function M.start(input)
  local data = model.normalize(input)
  if active then
    M.save()
  end
  -- Save new semantic data even when the source is currently unavailable.
  storage.save(config.storage.path, data)
  reveal(data, data.current_step)
  M.save()
  return M.current()
end

function M.open(id)
  local data = storage.open(config.storage.path, id)
  if active then
    M.save()
    -- Reopening the same tour must include just-reconciled edits.
    if active.id == id then
      data = vim.deepcopy(active)
    end
  end
  reveal(data, data.current_step)
  M.save()
  return M.current()
end

function M.resume()
  local data = storage.recent(config.storage.path, project.root())
  assert(data, "no saved tour for project " .. project.root())
  return M.open(data.id)
end

function M.goto_step(index)
  require_active()
  assert(
    type(index) == "number" and index == math.floor(index) and index >= 1 and index <= #active.steps,
    "step index must be between 1 and " .. #active.steps
  )
  reconcile()
  reveal(active, index)
  autosave()
  return M.current()
end

function M.next()
  require_active()
  return M.goto_step(math.min(active.current_step + 1, #active.steps))
end

function M.prev()
  require_active()
  return M.goto_step(math.max(active.current_step - 1, 1))
end

function M.close()
  if not active then
    return
  end
  local ok, err = pcall(M.save)
  render.clear(runtime)
  runtime = nil
  showing = false
  if not ok then
    error(err, 0)
  end
end

function M.finish()
  require_active()
  active.completed = true
  M.close()
end

function M.restart()
  require_active()
  reconcile()
  reveal(active, 1)
  active.completed = false
  M.save()
  return M.current()
end

function M.current()
  reconcile()
  return active and vim.deepcopy(active) or nil
end

function M.statusline()
  if not active or not showing then
    return ""
  end
  -- Escape percent signs for direct inclusion in a statusline format.
  return ("Tour %d/%d · %s")
    :format(active.current_step, #active.steps, active.steps[active.current_step].title)
    :gsub("%%", "%%%%")
end

function M.load(path)
  return M.start(storage.read(vim.fs.normalize(vim.fs.abspath(path))))
end

function M.list(opts)
  opts = opts or {}
  return storage.list(config.storage.path, not opts.all and project.root() or nil)
end

local function pick(items, opts, callback)
  vim.ui.select(items, opts, function(item)
    if item then
      local ok, err = pcall(callback, item)
      if not ok then
        vim.notify("tour.nvim: " .. err, vim.log.levels.ERROR)
      end
    end
  end)
end

function M.library(opts)
  pick(M.list(opts), {
    prompt = "Saved tours",
    format_item = function(data)
      return ("%s  %s%d/%d"):format(
        data.title,
        data.completed and "✓ " or "",
        data.current_step,
        #data.steps
      )
    end,
  }, function(data)
    M.open(data.id)
  end)
end

function M.overview()
  require_active()
  local data = active
  local choices = {}
  for i, step in ipairs(data.steps) do
    local symbol = i == data.current_step and "●"
      or (data.completed or i < data.current_step) and "✓"
      or " "
    choices[i] = { index = i, label = ("%s %d  %s"):format(symbol, i, step.title) }
  end
  pick(choices, {
    prompt = data.title,
    format_item = function(item)
      return item.label
    end,
  }, function(item)
    if active == data then
      M.goto_step(item.index)
    end
  end)
end

function M.setup(opts)
  local version = vim.version()
  assert(version.major == 0 and version.minor == 13, "tour.nvim requires Neovim 0.13")
  local new_config = require("tour.config").make(opts)
  if active then
    M.close()
  end
  config = new_config
  render.highlights()
  local group = vim.api.nvim_create_augroup("tour.nvim", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = render.highlights })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if active then
        local ok, err = pcall(M.save)
        if not ok then
          vim.notify("tour.nvim: " .. err, vim.log.levels.ERROR)
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufUnload", {
    group = group,
    callback = function(event)
      if runtime and runtime.buf == event.buf then
        reconcile()
        autosave()
        render.clear(runtime)
        runtime = nil
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "WinResized", "BufWinEnter", "TextChanged", "TextChangedI" }, {
    group = group,
    callback = function()
      if runtime and showing then
        reconcile()
        render.draw(runtime, active, config.render)
      end
    end,
  })
  for action, lhs in pairs(config.mappings) do
    assert(
      vim.tbl_contains({ "next", "prev", "overview", "resume", "close" }, action),
      "unknown mapping: " .. action
    )
    vim.keymap.set("n", lhs, "<Plug>(tour-" .. action .. ")", { desc = "Tour " .. action })
  end
end

return M
