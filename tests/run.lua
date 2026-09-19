vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.o.hidden = true
vim.o.swapfile = false
vim.o.shadafile = "NONE"
local repo = vim.fn.getcwd()
local original_next_mapping = vim.fn.maparg("]t", "n")
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
local count, failures = 0, {}
local tour, root, store
local model = require("tour.model")
local storage = require("tour.storage")
local position = require("tour.position")
local text = require("tour.util.text")
local api = vim.api
local presentation = api.nvim_create_namespace("tour.presentation")
local tracking = api.nvim_create_namespace("tour.tracking")

local function eq(actual, expected)
  assert(
    vim.deep_equal(actual, expected),
    "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual)
  )
end
local function raises(fn, fragment)
  local ok, err = pcall(fn)
  assert(not ok, "expected failure containing " .. fragment)
  assert(tostring(err):find(fragment, 1, true), tostring(err))
end
local function range(a, b, ac, bc)
  return { start = { line = a, col = ac or 0 }, ["end"] = { line = b, col = bc or 0 } }
end
local function fixture()
  local steps = {}
  for i = 1, 4 do
    steps[i] = {
      title = "Concept " .. i,
      location = { file = "main.lua", range = range(i * 3, i * 3 + 2) },
      description = "An explanation of this conceptual region.\n\nIt remains distinct from the smaller notes.",
      annotations = {},
    }
  end
  return { version = 1, id = "test-tour", title = "Test tour", project_root = root, steps = steps }
end
local function marks(buf)
  return api.nvim_buf_get_extmarks(buf or 0, presentation, 0, -1, { details = true })
end
local function has(predicate)
  for _, mark in ipairs(marks()) do
    if predicate(mark[3], mark[4]) then
      return true
    end
  end
  return false
end
local function note(placement, message)
  return { range = range(4, 4, 2, 5), placement = placement, text = message }
end
local function fresh()
  for name in pairs(package.loaded) do
    if name == "tour" or name:match("^tour%.") then
      package.loaded[name] = nil
    end
  end
  tour = require("tour")
  tour.setup({ storage = { path = store }, render = { max_width = 45 } })
end
local function test(name, fn)
  count = count + 1
  if tour then
    pcall(tour.close)
  end
  root = tmp .. "/case-" .. count
  store = root .. "/state"
  vim.fn.mkdir(root .. "/.git", "p")
  local lines = {}
  for i = 1, 30 do
    lines[i] = ("  source_%02d = value"):format(i)
  end
  vim.fn.writefile(lines, root .. "/main.lua")
  vim.fn.chdir(root)
  fresh()
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    print("ok " .. count .. " - " .. name)
  else
    failures[#failures + 1] = name .. "\n" .. err
    print("not ok " .. count .. " - " .. name .. "\n" .. err)
  end
end

test("schema validation gives contextual errors", function()
  local data = fixture()
  data.steps[3].title = nil
  raises(function()
    model.normalize(data)
  end, "step 3.title")
  data = fixture()
  data.steps[4].location.range.start.line = 0
  raises(function()
    model.normalize(data)
  end, "step 4.location.range.start.line")
  data = fixture()
  data.steps[2].annotations = { note("sideways", "bad") }
  raises(function()
    model.normalize(data)
  end, 'unknown placement "sideways"')
  data.steps[2].annotations[1].range["end"] = nil
  raises(function()
    model.normalize(data)
  end, "step 2 annotation 1.range: range is missing end")
end)

test("validation rejects malformed structures and runtime fields", function()
  for _, change in ipairs({
    function(d)
      d.version = 2
    end,
    function(d)
      d.bufnr = 1
    end,
    function(d)
      d.steps = {}
    end,
    function(d)
      d.current_step = 8
    end,
    function(d)
      d.completed = "yes"
    end,
    function(d)
      d.steps[1].location.range = range(5, 3)
    end,
    function(d)
      d.steps[1].annotations = { note("inline") }
    end,
    function(d)
      d.steps[1].location.anchor = "a\nb"
    end,
    function(d)
      d.source = { callback = function() end }
    end,
    function(d)
      d.id = "../../elsewhere"
    end,
    function(d)
      d.created_at = "yesterday"
    end,
    function(d)
      d.steps[1].id = "a"
      d.steps[2].id = "a"
    end,
  }) do
    local data = fixture()
    change(data)
    assert(not pcall(model.normalize, data), "malformed data must fail validation")
  end
end)

test("normalization supplies defaults without mutating input", function()
  local data = fixture()
  data.id, data.project_root = nil, nil
  local before = vim.deepcopy(data)
  local normalized = model.normalize(data)
  eq(data, before)
  eq(normalized.current_step, 1)
  eq(normalized.completed, false)
  eq(normalized.project_root, root)
  assert(normalized.id:match("^tour%-"))
  assert(normalized.created_at:match("Z$"))
end)

test("position conversion and exclusive ends", function()
  local row, col, opts = position.extmark(range(1, 3, 2, 4))
  eq({ row, col, opts.end_row, opts.end_col }, { 0, 2, 2, 4 })
  eq(position.point(0, 2), { line = 1, col = 2 })
  eq(position.last_line(range(1, 3)), 2)
end)

test("project relative and canonical paths", function()
  local data = fixture()
  data.steps[1].location.file = root .. "/./main.lua"
  data.steps[2].location.file = "/tmp/outside.lua"
  local normalized = model.normalize(data)
  eq(normalized.steps[1].location.file, "main.lua")
  eq(normalized.steps[2].location.file, "/tmp/outside.lua")
  assert(vim.uv.fs_symlink(root, root .. "-link"))
  eq(require("tour.project").root(root .. "-link"), root)
end)

test("project discovery finds worktree .git file and cwd fallback", function()
  vim.fn.mkdir(root .. "/work/deep", "p")
  vim.fn.writefile({ "gitdir: /somewhere" }, root .. "/work/.git")
  vim.fn.chdir(root .. "/work/deep")
  eq(require("tour.project").root(), root .. "/work")
  vim.fn.mkdir(tmp .. "/no-git", "p")
  vim.fn.chdir(tmp .. "/no-git")
  local fs_root = vim.fs.root
  vim.fs.root = function()
    return nil
  end
  local discovered = require("tour.project").root()
  vim.fs.root = fs_root
  eq(discovered, tmp .. "/no-git")
end)

test("JSON roundtrip preserves provenance and semantic data", function()
  local data = fixture()
  data.source = { kind = "generated", nested = { true, 4, vim.NIL } }
  data = model.normalize(data)
  storage.save(store, data)
  eq(storage.open(store, data.id), data)
end)

test("atomic replacement leaves no temporary files", function()
  local path = store .. "/data.json"
  storage.atomic_write(path, { value = 1 })
  storage.atomic_write(path, { value = 2 })
  eq(storage.read(path), { value = 2 })
  eq(vim.fn.glob(path .. ".tmp-*", false, true), {})
end)

test("failed atomic rename preserves previous JSON and removes temp", function()
  local path = store .. "/data.json"
  storage.atomic_write(path, { value = 1 })
  local rename = vim.uv.fs_rename
  vim.uv.fs_rename = function()
    return nil, "injected rename failure"
  end
  local ok, err = pcall(storage.atomic_write, path, { value = 2 })
  vim.uv.fs_rename = rename
  assert(
    not ok and err:find("injected rename failure", 1, true),
    "expected injected rename failure"
  )
  eq(storage.read(path), { value = 1 })
  eq(vim.fn.glob(path .. ".tmp-*", false, true), {})
end)

test("multiple tours and recent project tracking", function()
  local a = fixture()
  tour.start(a)
  local b = fixture()
  b.id = "second"
  tour.start(b)
  eq(#tour.list(), 2)
  eq(storage.recent(store, root).id, "second")
  tour.open(a.id)
  eq(storage.recent(store, root).id, a.id)
end)

test("index recovery scans valid saved tours", function()
  tour.start(fixture())
  vim.fn.writefile({ "broken" }, store .. "/index.json")
  eq(storage.recent(store, root).id, "test-tour")
  storage.atomic_write(store .. "/index.json", { version = 1, projects = { 42 } })
  tour.save()
  eq(storage.read(store .. "/index.json").projects[root], "test-tour")
end)

test("tour ID cannot overwrite another project's data", function()
  tour.start(fixture())
  local other = fixture()
  other.project_root = tmp
  raises(function()
    storage.save(store, model.normalize(other))
  end, "another project")
  eq(storage.open(store, "test-tour").project_root, root)
end)

test("next advances a conceptual step", function()
  tour.start(fixture())
  tour.next()
  eq(tour.current().current_step, 2)
  eq(api.nvim_win_get_cursor(0)[1], 6)
end)

test("previous and navigation boundaries", function()
  tour.start(fixture())
  tour.prev()
  eq(tour.current().current_step, 1)
  tour.goto_step(4)
  tour.next()
  eq(tour.current().current_step, 4)
  eq(tour.current().completed, false)
  tour.prev()
  eq(tour.current().current_step, 3)
end)

test("goto validates index and jumps directly", function()
  tour.start(fixture())
  tour.goto_step(3)
  eq(tour.current().current_step, 3)
  raises(function()
    tour.goto_step(0)
  end, "step index")
  eq(tour.current().current_step, 3)
end)

test("cursor moves do not advance tour", function()
  tour.start(fixture())
  api.nvim_win_set_cursor(0, { 28, 0 })
  eq(tour.current().current_step, 1)
end)

test("buffer switches and detours do not advance tour", function()
  tour.start(fixture())
  tour.goto_step(3)
  for _ = 1, 5 do
    api.nvim_set_current_buf(api.nvim_create_buf(true, false))
  end
  eq(tour.current().current_step, 3)
  tour.next()
  eq(tour.current().current_step, 4)
  eq(api.nvim_buf_get_name(0), root .. "/main.lua")
end)

test("close preserves progress and clears presentation", function()
  tour.start(fixture())
  tour.next()
  local buf = api.nvim_get_current_buf()
  tour.close()
  eq(storage.open(store, "test-tour").current_step, 2)
  eq(marks(buf), {})
  eq(api.nvim_buf_get_extmarks(buf, tracking, 0, -1, {}), {})
  eq(tour.statusline(), "")
end)

test("finish preserves completion and completed tours replay", function()
  tour.start(fixture())
  tour.goto_step(4)
  tour.finish()
  eq(storage.open(store, "test-tour").completed, true)
  eq(marks(), {})
  tour.open("test-tour")
  tour.prev()
  eq(tour.current().current_step, 3)
  eq(tour.current().completed, true)
end)

test("restart resets step and completion", function()
  tour.start(fixture())
  tour.goto_step(4)
  tour.finish()
  tour.restart()
  eq(tour.current().current_step, 1)
  eq(tour.current().completed, false)
  assert(#marks() > 0, "expected reconstructed presentation")
end)

test("integration: detour save clear state resume reconstructs step three", function()
  tour.start(fixture())
  tour.goto_step(3)
  local original = api.nvim_get_current_buf()
  api.nvim_set_current_buf(api.nvim_create_buf(true, false))
  eq(tour.current().current_step, 3)
  tour.save()
  -- Simulate a fresh process: discard Lua state and runtime decorations.
  api.nvim_buf_clear_namespace(original, presentation, 0, -1)
  api.nvim_buf_clear_namespace(original, tracking, 0, -1)
  fresh()
  eq(tour.current(), nil)
  tour.resume()
  eq(tour.current().current_step, 3)
  eq(api.nvim_get_current_buf(), original)
  assert(#marks() > 0, "expected reconstructed presentation")
end)

test("main description renders above target including header", function()
  tour.start(fixture())
  assert(has(function(_, details)
    return details.virt_lines_above and details.virt_lines[1][1][1]:find("Tour 1/4", 1, true)
  end))
end)

test("multiline wrapping preserves paragraphs and limits display width", function()
  eq(text.wrap("one two three\n\nfour", 7), { "one two", "three", "", "four" })
  for _, line in ipairs(text.wrap("漢字漢字 café averylongword", 6)) do
    assert(vim.fn.strdisplaywidth(line) <= 6, "Unicode line exceeds width")
  end
  eq(text.wrap("abcdefgh", 3), { "abc", "def", "gh" })
  tour.start(fixture())
  for _, mark in ipairs(marks()) do
    for _, line in ipairs(mark[4].virt_lines or {}) do
      assert(vim.fn.strdisplaywidth(line[1][1]) <= 45, "virtual line exceeds configured width")
    end
  end
end)

for _, placement in ipairs({ "above", "below", "inline", "eol", "highlight" }) do
  test(placement .. " annotation uses the expected extmark placement", function()
    local data = fixture()
    data.steps[1].annotations =
      { note(placement, placement ~= "highlight" and "Small note" or nil) }
    tour.start(data)
    assert(has(function(_, details)
      if placement == "above" or placement == "below" then
        return details.virt_lines
          and details.virt_lines[1][1][1]:find("Small note", 1, true)
          and (not not details.virt_lines_above) == (placement == "above")
      elseif placement == "highlight" then
        return details.hl_group == "TourHighlight" and details.end_col == 5
      end
      return details.virt_text_pos == placement
    end))
  end)
end

test("range highlight and number-column indication coexist", function()
  tour.start(fixture())
  assert(has(function(_, d)
    return d.hl_group == "TourRange"
  end))
  assert(has(function(_, d)
    return d.number_hl_group == "TourCurrent"
  end))
end)

test("all five annotations remain one conceptual step", function()
  local data = fixture()
  for _, p in ipairs({ "above", "below", "inline", "eol", "highlight" }) do
    data.steps[1].annotations[#data.steps[1].annotations + 1] = note(p, "A note")
  end
  tour.start(data)
  eq(#tour.current().steps, 4)
  eq(#api.nvim_buf_get_extmarks(0, tracking, 0, -1, {}), 6)
  tour.next()
  eq(tour.current().current_step, 2)
end)

test("long inline and EOL explanations spill into virtual lines", function()
  local data = fixture()
  data.steps[1].annotations =
    { note("inline", string.rep("overflow ", 30)), note("eol", "first\nsecond") }
  tour.start(data)
  assert(has(function(_, d)
    return d.virt_text and d.virt_lines and #d.virt_lines > 1
  end))
  for _, mark in ipairs(marks()) do
    for _, line in ipairs(mark[4].virt_lines or {}) do
      assert(vim.fn.strdisplaywidth(line[1][1]) <= 45, "virtual line exceeds configured width")
    end
  end
end)

test("changing steps removes old buffer decorations", function()
  local data = fixture()
  vim.fn.writefile(vim.fn.readfile(root .. "/main.lua"), root .. "/other.lua")
  data.steps[2].location.file = "other.lua"
  tour.start(data)
  local old = api.nvim_get_current_buf()
  tour.next()
  eq(marks(old), {})
  eq(api.nvim_buf_get_extmarks(old, tracking, 0, -1, {}), {})
  assert(#marks() > 0, "expected reconstructed presentation")
end)

test("rendering never changes source or modified flag", function()
  local original = vim.fn.readfile(root .. "/main.lua")
  local data = fixture()
  data.steps[1].annotations = { note("inline", "explanation") }
  tour.start(data)
  tour.next()
  tour.prev()
  tour.close()
  eq(api.nvim_buf_get_lines(0, 0, -1, false), original)
  eq(vim.bo.modified, false)
end)

test("anchor relocation shifts primary and annotation ranges", function()
  local data = fixture()
  data.steps[1].location.anchor = "source_03"
  data.steps[1].annotations = { note("below", "moves too") }
  local lines = vim.fn.readfile(root .. "/main.lua")
  table.insert(lines, 1, "inserted")
  table.insert(lines, 1, "inserted again")
  vim.fn.writefile(lines, root .. "/main.lua")
  tour.start(data)
  eq(tour.current().steps[1].location.range.start.line, 5)
  eq(tour.current().steps[1].annotations[1].range.start.line, 6)
end)

test("ambiguous anchors choose nearest occurrence, tie chooses earlier", function()
  local data = fixture()
  local lines = vim.fn.readfile(root .. "/main.lua")
  lines[2], lines[4], lines[20] = "duplicate", "duplicate", "duplicate"
  vim.fn.writefile(lines, root .. "/main.lua")
  data.steps[1].location.anchor = "duplicate"
  tour.start(data)
  eq(tour.current().steps[1].location.range.start.line, 2)
end)

test("missing anchor falls back to a valid saved range", function()
  local data = fixture()
  data.steps[1].location.anchor = "not present"
  tour.start(data)
  eq(tour.current().steps[1].location.range.start.line, 3)
end)

test("missing file navigation preserves current progress and UI", function()
  local data = fixture()
  data.steps[2].location.file = "missing.lua"
  tour.start(data)
  local before = marks()
  raises(tour.next, "target file is missing")
  eq(tour.current().current_step, 1)
  eq(marks(), before)
  eq(storage.open(store, "test-tour").current_step, 1)
end)

test("unresolvable new tour is still recoverable from storage", function()
  local data = fixture()
  data.steps[1].location.file = "missing.lua"
  raises(function()
    tour.start(data)
  end, "target file is missing")
  eq(storage.open(store, data.id).title, data.title)
end)

test("invalid target positions fail without clamping", function()
  local data = fixture()
  data.steps[1].location.range.start.col = 100
  raises(function()
    tour.start(data)
  end, "cannot resolve range")
end)

test("UTF-8 positions use bytes and reject split characters", function()
  eq(position.valid(range(1, 1, 0, 2), { "éx" }), true)
  eq(position.valid(range(1, 1, 0, 1), { "éx" }), false)
end)

test("runtime extmarks follow edits during detours and reconcile on save", function()
  local data = fixture()
  data.steps[1].annotations = { note("below", "tracked") }
  tour.start(data)
  local buf = api.nvim_get_current_buf()
  api.nvim_buf_set_lines(buf, 0, 0, false, { "inserted", "inserted" })
  api.nvim_set_current_buf(api.nvim_create_buf(true, false))
  tour.save()
  local saved = storage.open(store, data.id)
  eq(saved.steps[1].location.range.start.line, 5)
  eq(saved.steps[1].location.range["end"].line, 7)
  eq(saved.steps[1].annotations[1].range.start.line, 6)
  assert(saved.steps[1].location.anchor:find("source_03", 1, true))
  eq(saved.current_step, 1)
end)

test("gravity excludes insertions at start and end boundaries", function()
  local data = fixture()
  data.steps[1].location.range = range(3, 3, 2, 8)
  tour.start(data)
  api.nvim_buf_set_text(0, 2, 2, 2, 2, { "abc" })
  eq(tour.current().steps[1].location.range, range(3, 3, 5, 11))
  api.nvim_buf_set_text(0, 2, 11, 2, 11, { "tail" })
  eq(tour.current().steps[1].location.range, range(3, 3, 5, 11))
end)

test("deleting tracked region keeps a valid durable range", function()
  tour.start(fixture())
  api.nvim_buf_set_lines(0, 0, -1, false, { "" })
  tour.save()
  local saved = storage.open(store, "test-tour")
  eq(saved.steps[1].location.range, range(1, 1))
end)

test("buffer unload reconciles positions before extmarks disappear", function()
  tour.start(fixture())
  local buf = api.nvim_get_current_buf()
  api.nvim_buf_set_lines(buf, 0, 0, false, { "new" })
  api.nvim_buf_delete(buf, { force = true })
  eq(storage.open(store, "test-tour").steps[1].location.range.start.line, 4)
  tour.save()
end)

test("all saved examples validate and load", function()
  vim.fn.chdir(repo)
  for _, path in ipairs(vim.fn.glob(repo .. "/examples/*.json", false, true)) do
    local data = storage.read(path)
    model.normalize(data)
    tour.load(path)
    for i = 1, #data.steps do
      tour.goto_step(i)
      assert(#marks() > 0, "expected reconstructed presentation")
    end
    tour.close()
  end
end)

test("plugin leaves signcolumn, windows and other namespaces alone", function()
  local signcolumn = vim.o.signcolumn
  local wins = api.nvim_list_wins()
  tour.start(fixture())
  local ns = api.nvim_create_namespace("unrelated-plugin")
  local id = api.nvim_buf_set_extmark(0, ns, 0, 0, { sign_text = "+" })
  tour.next()
  tour.close()
  eq(vim.o.signcolumn, signcolumn)
  eq(api.nvim_list_wins(), wins)
  assert(#api.nvim_buf_get_extmark_by_id(0, ns, id, {}) > 0, "unrelated mark was deleted")
end)

test("statusline reflects tour position independently of detours", function()
  eq(tour.statusline(), "")
  tour.start(fixture())
  tour.goto_step(3)
  api.nvim_set_current_buf(api.nvim_create_buf(true, false))
  eq(tour.statusline(), "Tour 3/4 · Concept 3")
  tour.close()
  eq(tour.statusline(), "")
end)

test("project scoped resume and all-project library", function()
  local first = fixture()
  tour.start(first)
  tour.goto_step(3)
  local second_root = root .. "/other-project"
  vim.fn.mkdir(second_root .. "/.git", "p")
  vim.fn.writefile(vim.fn.readfile(root .. "/main.lua"), second_root .. "/main.lua")
  local second = fixture()
  second.project_root, second.id = second_root, "other-tour"
  tour.start(second)
  tour.goto_step(2)
  vim.fn.chdir(root)
  tour.resume()
  eq(tour.current().id, first.id)
  eq(tour.current().current_step, 3)
  eq(#tour.list(), 1)
  eq(#tour.list({ all = true }), 2)
  vim.fn.chdir(second_root)
  tour.resume()
  eq(tour.current().id, second.id)
  eq(tour.current().current_step, 2)
end)

test("current returns an independent semantic copy", function()
  tour.start(fixture())
  local copy = tour.current()
  copy.current_step = 4
  copy.steps[1].title = "mutated"
  eq(tour.current().current_step, 1)
  eq(tour.current().steps[1].title, "Concept 1")
end)

test("autosave off still saves explicitly and on close", function()
  tour.setup({ storage = { path = store, autosave = false } })
  tour.start(fixture())
  tour.next()
  eq(storage.open(store, "test-tour").current_step, 1)
  tour.close()
  eq(storage.open(store, "test-tour").current_step, 2)
end)

test("overview jumps and stale picker callbacks cannot change a new tour", function()
  tour.start(fixture())
  local old_select = vim.ui.select
  local callback, items
  vim.ui.select = function(choices, _, cb)
    items, callback = choices, cb
  end
  tour.overview()
  vim.ui.select = old_select
  callback(items[3])
  eq(tour.current().current_step, 3)
  local other = fixture()
  other.id = "another"
  tour.start(other)
  callback(items[4])
  eq(tour.current().current_step, 1)
end)

test("commands and Plug mappings are registered without default global keys", function()
  local commands = api.nvim_get_commands({})
  for _, name in ipairs({
    "Resume",
    "Next",
    "Prev",
    "Goto",
    "Open",
    "List",
    "Overview",
    "Save",
    "Close",
    "Finish",
    "Restart",
    "Load",
  }) do
    assert(commands["Tour" .. name], "missing command " .. name)
  end
  assert(vim.fn.maparg("<Plug>(tour-next)", "n") ~= "", "missing Plug mapping")
  eq(vim.fn.maparg("]t", "n"), original_next_mapping)
  tour.start(fixture())
  vim.cmd.TourGoto("3")
  vim.cmd.TourNext()
  eq(tour.current().current_step, 4)
end)

test("narrow-window reflow uses current text width", function()
  tour.start(fixture())
  vim.cmd.vsplit()
  api.nvim_win_set_width(0, 22)
  api.nvim_exec_autocmds("WinResized", {})
  local width = api.nvim_win_get_width(0) - vim.fn.getwininfo(api.nvim_get_current_win())[1].textoff
  for _, mark in ipairs(marks()) do
    for _, line in ipairs(mark[4].virt_lines or {}) do
      assert(vim.fn.strdisplaywidth(line[1][1]) <= width, "virtual line exceeds viewport")
    end
  end
  vim.cmd.close()
end)

test("VimLeavePre saves progress for a fresh Neovim process", function()
  local script = root .. "/child.lua"
  local data = fixture()
  vim.fn.writefile(
    vim.split(
      table.concat({
        "vim.opt.runtimepath:prepend(" .. string.format("%q", repo) .. ")",
        "local t = require('tour')",
        "t.setup({storage={path=" .. string.format("%q", store) .. ",autosave=false}})",
        "t.start(" .. vim.inspect(data) .. ")",
        "t.goto_step(3)",
        "vim.cmd('qa!')",
      }, "\n"),
      "\n",
      { plain = true }
    ),
    script
  )
  local result = vim
    .system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-l", script }, { text = true })
    :wait()
  assert(result.code == 0, result.stderr .. result.stdout)
  eq(storage.open(store, data.id).current_step, 3)
  tour.resume()
  eq(tour.current().current_step, 3)
  assert(#marks() > 0, "expected reconstructed presentation")
end)

test("close clears UI even if persistence fails", function()
  tour.start(fixture())
  local live_storage = require("tour.storage")
  local save = live_storage.save
  live_storage.save = function()
    error("injected disk failure")
  end
  local ok, err = pcall(tour.close)
  live_storage.save = save
  assert(not ok and tostring(err):find("injected disk failure", 1, true), "expected save failure")
  eq(marks(), {})
  eq(tour.statusline(), "")
  eq(tour.current().current_step, 1)
  tour.save()
end)

test("undo restores the tracked range", function()
  tour.start(fixture())
  api.nvim_buf_set_lines(0, 0, 0, false, { "new first line" })
  eq(tour.current().steps[1].location.range.start.line, 4)
  vim.cmd.undo()
  eq(tour.current().steps[1].location.range.start.line, 3)
end)

test("Neovim help tags generate successfully", function()
  local directory = root .. "/help"
  vim.fn.mkdir(directory, "p")
  vim.fn.writefile(vim.fn.readfile(repo .. "/doc/tour.txt"), directory .. "/tour.txt")
  vim.cmd.helptags(directory)
  local tags = table.concat(vim.fn.readfile(directory .. "/tags"), "\n")
  assert(tags:find("tour.nvim", 1, true), "missing main help tag")
  assert(tags:find(":TourResume", 1, true), "missing command help tag")
end)

test("attached UI displays explanation next to actual source", function()
  local child = vim.fn.jobstart(
    { vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-i", "NONE" },
    { rpc = true }
  )
  local ok, err = xpcall(function()
    vim.rpcrequest(child, "nvim_ui_attach", 80, 30, {})
    local data = fixture()
    data.steps[1].description = "A visible explanation above the function."
    data.steps[1].annotations = { note("below", "A smaller note.") }
    vim.rpcrequest(
      child,
      "nvim_exec_lua",
      [[
      local repo, store, data = ...
      vim.opt.runtimepath:prepend(repo)
      vim.o.swapfile = false
      local t = require('tour')
      t.setup({ storage = { path = store } })
      t.start(data)
      vim.cmd.redraw()
    ]],
      { repo, store, data }
    )
    local screen = vim.rpcrequest(
      child,
      "nvim_exec_lua",
      [[
      local lines = {}
      for row = 1, 30 do
        local line = ''
        for col = 1, 80 do line = line .. vim.fn.screenstring(row, col) end
        lines[#lines + 1] = line
      end
      return table.concat(lines, '\n')
    ]],
      {}
    )
    local header = assert(screen:find("Tour 1/4", 1, true))
    local description = assert(screen:find("A visible explanation", 1, true))
    local source = assert(screen:find("source_03 = value", 1, true))
    assert(header < description and description < source, "description must precede actual code")
    assert(screen:find("A smaller note.", 1, true), "annotation missing from screen")
  end, debug.traceback)
  vim.fn.jobstop(child)
  assert(ok, err)
end)

test("EOL notes on half-open line ranges attach to the last covered line", function()
  local data = fixture()
  data.steps[1].annotations = {
    { range = range(4, 5), placement = "eol", text = "last covered" },
  }
  tour.start(data)
  local found = false
  for _, mark in ipairs(marks()) do
    if mark[4].virt_text_pos == "eol" then
      eq(mark[2], position.row(4))
      found = true
    end
  end
  assert(found, "missing EOL annotation")
end)

if tour then
  pcall(tour.close)
end
api.nvim_del_augroup_by_name("tour.nvim")
vim.fn.chdir(repo)
vim.fn.delete(tmp, "rf")
print(("\n%d tests, %d failures"):format(count, #failures))
if #failures > 0 then
  vim.cmd("cquit 1")
end
vim.cmd("qa!")
