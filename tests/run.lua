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

test("active region has an independent gutter without code underlining", function()
  tour.start(fixture())
  assert(vim.wo.statuscolumn ~= "", "missing tour gutter")
  assert(not has(function(_, d)
    return d.hl_group == "TourRange" or d.number_hl_group == "TourCurrent"
  end), "primary region must not alter source or number highlights")
  local drawn = api.nvim_eval_statusline(vim.wo.statuscolumn, { use_statuscol_lnum = 3 }).str
  assert(drawn:find("▎", 1, true), "gutter must mark covered lines")
  local outside = api.nvim_eval_statusline(vim.wo.statuscolumn, { use_statuscol_lnum = 5 }).str
  assert(not outside:find("▎", 1, true), "exclusive end must not mark the next line")
  tour.close()
  eq(vim.wo.statuscolumn, "")
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
    local checked = tour.validate(data)
    assert(checked.ok, vim.inspect(checked.errors))
    local receipt = tour.load_checked(path, { revisions = checked.revisions })
    assert(receipt.ok and receipt.persisted and receipt.displayed, vim.inspect(receipt.errors))
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
      vim.wo.number = true
      vim.wo.relativenumber = true
      vim.wo.signcolumn = 'yes'
      local t = require('tour')
      t.setup({ storage = { path = store } })
      t.start(data)
      vim.api.nvim_buf_set_extmark(0, vim.api.nvim_create_namespace('git-sign-fixture'), 2, 0, {
        sign_text = '+', sign_hl_group = 'DiffAdd', priority = 10,
      })
      assert(vim.wo.signcolumn == 'yes', 'tour changed the sign column')
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
    local source_line = assert(screen:match("([^\n]*source_03 = value[^\n]*)"))
    assert(source_line:find("+", 1, true), "Git sign was hidden")
    assert(source_line:find("▎", 1, true), "tour gutter missing beside Git sign")
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

test("gutter preserves custom statuscolumns and subsequent user changes", function()
  local custom = "%s%=%l CUSTOM "
  vim.wo.statuscolumn = custom
  tour.start(fixture())
  eq(vim.wo.statuscolumn, custom)
  tour.close()
  eq(vim.wo.statuscolumn, custom)
  vim.wo.statuscolumn = ""
  tour.restart()
  vim.wo.statuscolumn = custom
  tour.close()
  eq(vim.wo.statuscolumn, custom)
  vim.wo.statuscolumn = ""
end)

test("gutter leaves detour windows and follows new views of the target", function()
  tour.start(fixture())
  local source = api.nvim_get_current_buf()
  local original = api.nvim_get_current_win()
  vim.cmd.vsplit()
  local other = api.nvim_get_current_win()
  api.nvim_set_current_buf(api.nvim_create_buf(true, false))
  eq(vim.wo.statuscolumn, "")
  assert(vim.wo[original].statuscolumn ~= "", "visible target lost its gutter")
  local drawn = api.nvim_eval_statusline(
    vim.wo[original].statuscolumn,
    { winid = original, use_statuscol_lnum = 3 }
  ).str
  assert(drawn:find("▎", 1, true), "non-current target window lost its range indicator")
  api.nvim_set_current_buf(source)
  assert(vim.wo.statuscolumn ~= "", "reopened target needs a gutter")
  tour.close()
  eq(vim.wo[original].statuscolumn, "")
  eq(vim.wo[other].statuscolumn, "")
  vim.cmd.close()
end)

test("annotation wrapping marks each note once and widens overflow", function()
  local data = fixture()
  data.steps[1].annotations = { note("below", string.rep("small details ", 8)) }
  tour.start(data)
  local found = false
  for _, mark in ipairs(marks()) do
    local lines = mark[4].virt_lines
    if lines and lines[1][1][1]:find("›", 1, true) then
      assert(#lines > 1, "expected wrapped note")
      assert(not lines[2][1][1]:find("›", 1, true), "continuation repeats note marker")
      found = true
    end
  end
  assert(found, "missing annotation")
  eq(text.wrap("one two three four five", 18, 7), { "one two", "three four five" })
end)

test("theme-derived prose has readable hierarchy and respects overrides", function()
  local names = { "Normal", "Comment", "TourDescription", "TourAnnotation" }
  local previous = {}
  for _, name in ipairs(names) do
    previous[name] = api.nvim_get_hl(0, { name = name })
  end
  local ok, err = xpcall(function()
    api.nvim_set_hl(0, "Normal", { fg = 0xdddddd, bg = 0x111111 })
    api.nvim_set_hl(0, "Comment", { fg = 0x444444 })
    api.nvim_set_hl(0, "TourDescription", {})
    api.nvim_set_hl(0, "TourAnnotation", {})
    require("tour.render").highlights()
    local description = api.nvim_get_hl(0, { name = "TourDescription", link = false })
    local annotation = api.nvim_get_hl(0, { name = "TourAnnotation", link = false })
    assert(
      description.fg > annotation.fg and annotation.fg > 0x444444,
      "prose hierarchy is too dim or reversed"
    )
    assert(annotation.italic, "notes should be visually distinct from the main description")
    api.nvim_set_hl(0, "TourAnnotation", { fg = 0x123456 })
    require("tour.render").highlights()
    eq(api.nvim_get_hl(0, { name = "TourAnnotation", link = false }).fg, 0x123456)
  end, debug.traceback)
  for _, name in ipairs(names) do
    api.nvim_set_hl(0, name, previous[name])
  end
  assert(ok, err)
end)

test("displayed titles omit duplicate numbering without changing durable data", function()
  local data = fixture()
  data.steps[1].title = "1. Concept one"
  tour.start(data)
  eq(tour.statusline(), "Tour 1/4 · Concept one")
  eq(tour.current().steps[1].title, "1. Concept one")
  eq(storage.open(store, data.id).steps[1].title, "1. Concept one")
  eq(text.step_title("2.5 protocol", 2), "2.5 protocol")
  eq(text.step_title("2. Section", 3), "2. Section")
  assert(
    has(function(_, d)
      return d.virt_lines and d.virt_lines[1][1][1] == "Tour 1/4 · Concept one"
    end),
    "header still repeats the step number"
  )
end)

test("source inspection returns unsaved raw lines and revision without opening files", function()
  local before = api.nvim_list_bufs()
  local current = api.nvim_get_current_buf()
  local read = tour.read_source("main.lua", { project_root = root })
  assert(read.ok, vim.inspect(read.errors))
  eq(read.origin, "disk")
  eq(read.lines[1], "  source_01 = value")
  eq(read.bufnr, nil)
  eq(api.nvim_list_bufs(), before)
  eq(api.nvim_get_current_buf(), current)
  local buf = vim.fn.bufadd(root .. "/main.lua")
  vim.fn.bufload(buf)
  local loaded = tour.read_source("main.lua")
  eq(loaded.revision, read.revision)
  api.nvim_buf_set_lines(buf, 0, 1, true, { "\tλ unsaved" })
  read = tour.read_source("main.lua")
  eq(read.lines[1], "\tλ unsaved")
  eq(read.bufnr, buf)
  eq(read.changedtick, api.nvim_buf_get_changedtick(buf))
  eq(read.modified, true)
  eq(read.origin, "buffer")
  assert(read.revision ~= loaded.revision, "edits must change the revision")
  read.lines[1] = "caller edit"
  eq(api.nvim_buf_get_lines(buf, 0, 1, true), { "\tλ unsaved" })
end)

test("source inspection handles BOM CRLF empty files and absent final newline", function()
  local path = root .. "/dos.lua"
  local file = assert(io.open(path, "wb"))
  file:write("\239\187\191one\r\ntwo\r\n")
  file:close()
  local disk = tour.read_source(path)
  eq(disk.lines, { "one", "two" })
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  eq(tour.read_source(path).revision, disk.revision)
  vim.fn.writefile({}, root .. "/empty.lua")
  eq(tour.read_source("empty.lua").lines, { "" })
  vim.fn.writefile({ "no newline" }, root .. "/no-newline.lua", "b")
  eq(tour.read_source("no-newline.lua").lines, { "no newline" })
  local missing = tour.read_source("missing.lua")
  eq(missing.errors[1].code, "unreadable_file")
  eq(missing.errors[1].file, root .. "/missing.lua")
end)

test("literal resolver calculates UTF-8 tabs multiline and exclusive byte endpoints", function()
  vim.fn.writefile({ "\tλ = f(x)", "  return λ", "tail" }, root .. "/unicode.lua")
  local one = tour.resolve({ file = "unicode.lua", snippet = "λ = f(x)" })
  assert(one.ok, vim.inspect(one.errors))
  eq(one.range, range(1, 1, 1, 10))
  local multi = tour.resolve({ file = "unicode.lua", snippet = "f(x)\n  return λ" })
  assert(multi.ok, vim.inspect(multi.errors))
  eq(multi.range, range(1, 2, 6, 11))
  eq(multi.revision, one.revision)
  local ending = tour.resolve({ file = "unicode.lua", snippet = "return λ\n" })
  eq(ending.range, range(2, 3, 2, 0))
  local eof = tour.resolve({ file = "unicode.lua", snippet = "tail" })
  eq(eof.range, range(3, 3, 0, 4))
end)

test(
  "literal resolver reports ambiguity including overlapping matches and supports scope",
  function()
    vim.fn.writefile({ "banana", "banana" }, root .. "/duplicate.lua")
    local result = tour.resolve({ file = "duplicate.lua", snippet = "ana" })
    eq(result.ok, false)
    eq(result.errors[1].code, "ambiguous_snippet")
    eq(
      result.candidates,
      { range(1, 1, 1, 4), range(1, 1, 3, 6), range(2, 2, 1, 4), range(2, 2, 3, 6) }
    )
    result = tour.resolve({ file = "duplicate.lua", snippet = "ana", within = range(2, 2, 2, 6) })
    assert(result.ok, vim.inspect(result.errors))
    eq(result.range, range(2, 2, 3, 6))
    result = tour.resolve({ file = "duplicate.lua", snippet = "missing" })
    eq(result.errors[1].code, "snippet_not_found")
    eq(result.candidates, {})
    result = tour.resolve({ file = "duplicate.lua", snippet = "ana", within = range(1, 40) })
    eq(result.errors[1].code, "invalid_range")
    eq(result.errors[1].bounds.max_line, 2)
    eq(tour.resolve({ file = "duplicate.lua", snippet = "" }).errors[1].code, "invalid_request")
  end
)

test("whole-tour validation collects structural and live location errors together", function()
  local data = fixture()
  data.steps[1].title = nil
  data.steps[1].annotations = { note("sideways", "bad placement"), note("eol", "bad column") }
  data.steps[1].annotations[2].range["end"].col = 100
  data.steps[2].location.range = range(31, 35)
  data.steps[3].location.file = "missing.lua"
  data.steps[4].annotations = { note("highlight") }
  data.steps[4].annotations[1].range["end"] = nil
  local before = vim.deepcopy(data)
  local report = tour.validate(data)
  eq(report.ok, false)
  eq(report.data, nil)
  eq(data, before)
  local seen = {}
  for _, err in ipairs(report.errors) do
    seen[err.path] = err
    assert(err.file and err.step, vim.inspect(err))
  end
  assert(seen["step 1.title"], "missing error for step 1.title")
  assert(seen["step 1 annotation 1"], "missing error for step 1 annotation 1")
  local annotation = seen["step 1 annotation 2.range.end"]
  eq(annotation.annotation, 2)
  eq(annotation.range["end"].col, 100)
  eq(annotation.bounds.max_col, 19)
  eq(seen["step 2.location.range.start"].bounds.max_line, 30)
  assert(seen["step 2.location.range.end"], "missing error for step 2.location.range.end")
  eq(seen["step 3.location.file"].code, "unreadable_file")
  assert(seen["step 4 annotation 1.range"], "missing error for step 4 annotation 1.range")
end)

test(
  "validation and resolution leave editor presentation progress and storage untouched",
  function()
    tour.start(fixture())
    tour.goto_step(3)
    local semantic, before_marks = tour.current(), marks()
    local saved = storage.read(store .. "/tours/test-tour.json")
    local index = storage.read(store .. "/index.json")
    local cursor, buf = api.nvim_win_get_cursor(0), api.nvim_get_current_buf()
    local buffers, windows = api.nvim_list_bufs(), api.nvim_list_wins()
    local read_count = 0
    local autocmd = api.nvim_create_autocmd("BufReadPost", {
      callback = function()
        read_count = read_count + 1
      end,
    })
    vim.fn.writefile({ "new source" }, root .. "/unloaded.lua")
    local data = fixture()
    data.id = "unstarted"
    data.steps[4].location = { file = "unloaded.lua", range = range(1, 1, 0, 10) }
    local input = vim.deepcopy(data)
    local result = tour.validate(data)
    assert(result.ok, vim.inspect(result.errors))
    assert(result.data.steps[4].location.anchor, "missing derived anchor")
    eq(data, input)
    assert(
      tour.resolve({ file = "unloaded.lua", snippet = "new source" }).ok,
      "snippet resolution failed"
    )
    eq(read_count, 0)
    api.nvim_del_autocmd(autocmd)
    eq(api.nvim_list_bufs(), buffers)
    eq(api.nvim_list_wins(), windows)
    eq(api.nvim_get_current_buf(), buf)
    eq(api.nvim_win_get_cursor(0), cursor)
    eq(marks(), before_marks)
    eq(tour.current(), semantic)
    eq(storage.read(store .. "/tours/test-tour.json"), saved)
    eq(storage.read(store .. "/index.json"), index)
    eq(vim.fn.filereadable(store .. "/tours/unstarted.json"), 0)
  end
)

test(
  "whole-tour validation uses unsaved buffers and the same anchor relocation as navigation",
  function()
    local data = fixture()
    data.steps[4].location.anchor = "source_12"
    data.steps[4].annotations = { { range = range(13, 13, 2, 8), placement = "highlight" } }
    local buf = vim.fn.bufadd(root .. "/main.lua")
    vim.fn.bufload(buf)
    api.nvim_buf_set_lines(buf, 0, 0, true, { "inserted", "unsaved" })
    local result = tour.validate(data)
    assert(result.ok, vim.inspect(result.errors))
    eq(result.data.steps[4].location.range.start.line, 14)
    eq(result.data.steps[4].annotations[1].range.start.line, 15)
    eq(data.steps[4].location.range.start.line, 12)
    tour.start(result.data)
    tour.goto_step(4)
    eq(tour.current().steps[4].location.range, result.data.steps[4].location.range)
  end
)

test("UTF-8 boundaries are validated for every annotation", function()
  local data = fixture()
  vim.fn.writefile({ "λ end" }, root .. "/unicode.lua")
  data.steps[2].location = { file = "unicode.lua", range = range(1, 1, 0, 2) }
  data.steps[2].annotations = { { range = range(1, 1, 1, 2), placement = "highlight" } }
  local report = tour.validate(data)
  eq(#report.errors, 1)
  eq(report.errors[1].annotation, 1)
  assert(report.errors[1].message:find("UTF-8", 1, true))
end)

test("source revisions detect edits on disk and in loaded buffers", function()
  local read = tour.read_source("main.lua")
  local revisions = { [read.file] = read.revision }
  assert(tour.validate(fixture(), { revisions = revisions }).ok, "unchanged snapshot rejected")
  vim.fn.writefile({ "changed on disk" }, root .. "/main.lua")
  local result = tour.resolve({ file = "main.lua", snippet = "changed", revision = read.revision })
  eq(result.errors[1].code, "stale_source")
  result = tour.start_checked(fixture(), { revisions = revisions })
  eq(result.ok, false)
  eq(result.persisted, false)
  eq(result.errors[1].code, "stale_source")
  eq(tour.current(), nil)
  eq(vim.fn.isdirectory(store), 0)
  local buf = vim.fn.bufadd(root .. "/main.lua")
  vim.fn.bufload(buf)
  read = tour.read_source("main.lua")
  api.nvim_buf_set_lines(buf, 0, 1, true, { "unsaved edit" })
  eq(
    tour.resolve({ file = "main.lua", snippet = "unsaved", revision = read.revision }).errors[1].code,
    "stale_source"
  )
end)

test("checked activation rejects later failures while preserving the active tour", function()
  tour.start(fixture())
  tour.goto_step(2)
  local before, old_marks = tour.current(), marks()
  local replacement = fixture()
  replacement.id = "replacement"
  replacement.steps[4].location.file = "absent.lua"
  local receipt = tour.start_checked(replacement)
  eq(receipt.ok, false)
  eq(receipt.persisted, false)
  eq(receipt.displayed, false)
  eq(receipt.errors[1].step, 4)
  eq(tour.current(), before)
  eq(marks(), old_marks)
  eq(vim.fn.filereadable(store .. "/tours/replacement.json"), 0)
  eq(storage.recent(store, root).id, before.id)
end)

test("checked JSON loading returns a structured receipt and saves only semantic data", function()
  local path = root .. "/tour.json"
  storage.atomic_write(path, fixture())
  local read = tour.read_source("main.lua")
  local receipt = tour.load_checked(path, { revisions = { [read.file] = read.revision } })
  eq(receipt, {
    ok = true,
    id = "test-tour",
    title = "Test tour",
    current_step = 1,
    step_count = 4,
    persisted = true,
    displayed = true,
    errors = {},
  })
  assert(#marks() > 0, "presentation was not reconstructed")
  local saved = storage.open(store, receipt.id)
  eq(saved.current_step, 1)
  local json = vim.json.encode(saved)
  for _, name in ipairs({ "bufnr", "changedtick", "revision", "persisted", "displayed" }) do
    assert(not json:find('"' .. name .. '"', 1, true), "runtime metadata was persisted: " .. name)
  end
  vim.fn.writefile({ "invalid json" }, path)
  receipt = tour.load_checked(path)
  eq(receipt.errors[1].code, "invalid_json")
  eq(tour.current().id, "test-tour")
end)

test("checked loading catches source changes from buffer read hooks before saving", function()
  local autocmd = api.nvim_create_autocmd("BufReadPost", {
    pattern = root .. "/main.lua",
    callback = function(event)
      api.nvim_buf_set_lines(event.buf, 0, 0, true, { "hook changed source" })
    end,
  })
  local receipt = tour.start_checked(fixture())
  api.nvim_del_autocmd(autocmd)
  eq(receipt.ok, false)
  eq(receipt.persisted, false)
  eq(receipt.displayed, false)
  eq(receipt.errors[1].code, "stale_source")
  eq(tour.current(), nil)
  eq(vim.fn.isdirectory(store), 0)
end)

test("checked loading reports persistence failures without claiming success", function()
  local blocked = root .. "/blocked"
  vim.fn.writefile({ "not a directory" }, blocked)
  tour.setup({ storage = { path = blocked } })
  local receipt = tour.start_checked(fixture())
  eq(receipt.ok, false)
  eq(receipt.persisted, vim.NIL)
  eq(receipt.displayed, false)
  eq(receipt.errors[1].code, "persistence_failed")
  eq(tour.current(), nil)
end)

test("authoring interfaces handle malformed input and JSON roundtrip errors", function()
  for _, input in ipairs({ false, 3, vim.NIL, {}, { steps = { false } } }) do
    local result = tour.validate(input)
    assert(not result.ok and #result.errors > 0, "malformed input accepted")
    assert(vim.json.encode(result))
  end
  eq(tour.read_source(5).errors[1].code, "invalid_request")
  eq(tour.resolve(false).errors[1].code, "invalid_request")
  eq(tour.validate(fixture(), { revisions = false }).errors[1].code, "invalid_request")
  eq(tour.validate(fixture(), { revisions = { [1] = true } }).errors[1].code, "invalid_request")
end)

test("schema collection reports both endpoints without abandoning later locations", function()
  local data = fixture()
  data.steps[1].location.range = range(0, 0, -1, -2)
  data.steps[4].location.range = range(50, 51)
  local result = tour.validate(data)
  eq(#result.errors, 6)
  eq(result.errors[1].path, "step 1.location.range.start.line")
  eq(result.errors[2].path, "step 1.location.range.start.col")
  eq(result.errors[3].path, "step 1.location.range.end.line")
  eq(result.errors[4].path, "step 1.location.range.end.col")
  eq(result.errors[5].step, 4)
end)

test("checked loading survives the existing command-output JSON transport", function()
  local path = root .. "/tour.json"
  local opts_path = root .. "/options.json"
  storage.atomic_write(path, fixture())
  local read = tour.read_source("main.lua")
  storage.atomic_write(opts_path, { revisions = { [read.file] = read.revision } })
  local command = ([[lua local opts = vim.json.decode(table.concat(vim.fn.readfile(%q), "\n")); print(vim.json.encode(require('tour').load_checked(%q, opts)))]]):format(
    opts_path,
    path
  )
  local output = api.nvim_exec2(command, { output = true }).output
  local receipt = vim.json.decode(output)
  eq(receipt.ok, true)
  eq(receipt.persisted, true)
  eq(receipt.displayed, true)
  eq(receipt.step_count, 4)
  eq(tour.current().id, receipt.id)
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
