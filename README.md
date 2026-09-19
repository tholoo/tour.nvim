# tour.nvim

Durable guided code walkthroughs in Neovim, with inline annotations, free
exploration, and resumable progress.

**Neovim 0.13 only · No runtime dependencies · MIT licensed**

[Quick start](#try-a-tour) · [Lua API](#commands-and-api) ·
[Authoring reference](doc/authoring.md) · [Contributing](CONTRIBUTING.md)

A tour is an ordered explanation of a codebase. Each step explains one conceptual
region and can attach several smaller notes to expressions inside or around it.
Descriptions appear above the code; annotations are virtual text, virtual lines,
or highlights. They never become buffer contents.

Your editor position and your tour position are independent. Jump to definitions,
switch buffers, search, or edit while on step 4. `:TourNext` still takes you to
step 5. No detour mode, sidebar, dedicated tab, or workspace is required.

The plugin presents structured data. It does not call AI models, fetch PRs or
diffs, generate graphs, manage projects, or provide chat or an MCP bridge. An
external tool can produce a tour using any of those sources.

## Installation

Install with [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "tholoo/tour.nvim",
  opts = {},
}
```

Use Neovim 0.13, including compatible development builds. Older Neovim releases
are not supported. Nix is optional for users; it provides the pinned development
and test environment described below. The plugin has no Lua runtime dependencies.

For a local checkout, use `{ dir = "/path/to/tour.nvim", opts = {} }`, or place it
in `stdpath('data')/site/pack/local/start/tour.nvim`. Run
`:helptags /path/to/tour.nvim/doc` if your plugin manager does not generate tags,
then `:help tour.nvim`.

## Try a tour

The repository includes source fixtures and three loadable tours. From a checkout,
start a clean session with the pinned editor:

```sh
nix develop --command nvim --clean --cmd 'set runtimepath^=.' \
  -c 'lua require("tour").load("examples/annotated-function.json")'
```

With the plugin already installed, open Neovim from the checkout and run
`:TourLoad examples/annotated-function.json`.

Use `:TourNext`, `:TourPrev`, or `:TourOverview` to navigate. Jump to another file
at any point; the tour keeps its place. `:TourClose` hides it and saves progress.
`:TourResume` brings it back, including after restarting Neovim in the project.

For your own code, pass a Lua table to `require("tour").start(data)` or load v1 JSON
with `:TourLoad`. Tours may come from a human, another plugin, or any coding agent.
No model or provider integration is required. See the [complete example](#a-complete-tour)
and [agent workflow](#automatic-tours-from-coding-agents).

## Setup

Setup is optional; the first session operation initializes defaults. Read-only
authoring helpers do not initialize presentation.

```lua
require("tour").setup({
  storage = {
    path = vim.fn.stdpath("state") .. "/tour.nvim",
    autosave = true,
  },
  render = { max_width = 88 },
  mappings = {}, -- optional keys: next, prev, overview, resume, close
})

vim.keymap.set("n", "]t", "<Plug>(tour-next)")
vim.keymap.set("n", "[t", "<Plug>(tour-prev)")
vim.keymap.set("n", "<leader>to", "<Plug>(tour-overview)")
```

No global keys, statusline, signcolumn options, or window layout are installed.
These suggested keys replace any existing mappings (including Neovim defaults).
`<Plug>` mappings also exist for resume, close, finish, restart, and save.

For statusline integration, `require('tour').statusline()` returns
`Tour 4/8 · Retry policy`, or an empty string when presentation is closed. Percent
signs in titles are escaped for use in a statusline format string.

## Commands and API

```lua
local tour = require("tour")
tour.start(data)       -- validate, normalize, save, and display a new tour
tour.load(path)        -- read JSON and start it
tour.resume()          -- open this project's most recently active saved tour
tour.open(id)          -- open by globally unique saved ID
tour.next()            -- advance one conceptual step
tour.prev()            -- go back one conceptual step
tour.goto_step(3)      -- jump directly; indices are 1-based
tour.overview()        -- vim.ui.select of steps, with direct navigation
tour.list()            -- return saved tour data for this project
tour.list({ all = true }) -- return data for all projects
tour.save()            -- reconcile edits and persist
tour.close()           -- save and remove presentation
tour.finish()          -- mark completed, save, and remove presentation
tour.restart()         -- clear completed, save, display step 1
tour.current()         -- detached semantic copy, or nil before a tour is loaded
tour.statusline()      -- current presentation label, or ""
```

| Command | Action |
| --- | --- |
| `:TourResume` | Resume the current project's most recent tour |
| `:TourNext`, `:TourPrev` | Move between conceptual steps |
| `:TourGoto {index}` | Jump directly; supports index completion |
| `:TourOpen [id]` | Open by ID, or select a saved tour; supports ID completion |
| `:TourList[!]` | Select a saved tour; `!` includes all projects |
| `:TourOverview` | Select a step in the loaded tour |
| `:TourSave`, `:TourClose` | Save progress, or save and hide presentation |
| `:TourFinish`, `:TourRestart` | Complete or replay the loaded tour |
| `:TourLoad {json-file}` | Load external JSON; supports file completion |

Navigation/session operations raise contextual errors; commands report them with
`vim.notify`. The authoring helpers below return structured results instead.
Navigation clamps at the first/last step and never implicitly finishes a tour.
`finish()` preserves the current step, even when finishing early. Opening a
completed tour permits navigation and retains its completion flag until
`restart()`. `close()` retains the loaded semantic tour in memory, so `current()`,
`restart()`, `overview()`, and explicit navigation still work. It removes all
tracking/presentation marks; `statusline()` becomes empty.

Overview checkmarks indicate positions before the current step (or completion),
not a separately tracked visit history. Displayed titles omit a matching leading
step number (such as `2. ` on step 2); saved titles remain intact. `list()` returns
data; `:TourList` opens the picker. All returned data are copies, never mutable plugin internals.

## A complete tour

Run this from the repository root; it targets the included example source file.
One step explains the function while several annotations explain its details.

```lua
require("tour").start({
  version = 1,
  id = "retry-walkthrough", -- optional; otherwise generated
  project_root = ".", -- this example targets the current directory
  title = "How retries work",
  source = { kind = "manual" },
  steps = {
    {
      id = "retry-loop",
      title = "The retry lifecycle",
      location = {
        file = "examples/code/retry.lua",
        range = {
          start = { line = 3, col = 0 },
          ["end"] = { line = 15, col = 0 },
        },
        anchor = "function M.send(request, policy, transport)",
      },
      description = [[This function owns the retry lifecycle.

Retry policy stays separate from request execution, so the caller does
not need to understand which failures are transient.]],
      annotations = {
        {
          range = { start = { line = 7, col = 10 }, ["end"] = { line = 7, col = 16 } },
          placement = "inline",
          text = "A single attempt.",
        },
        {
          range = { start = { line = 8, col = 0 }, ["end"] = { line = 9, col = 0 } },
          placement = "below",
          text = "The policy decides whether another attempt is useful.",
        },
        {
          range = { start = { line = 11, col = 4 }, ["end"] = { line = 11, col = 19 } },
          placement = "highlight",
        },
      },
    },
  },
})
```

The three complete JSON examples are:

- [Request flow](examples/request-flow.json): receiving, routing, and recording a request.
- [Annotated function](examples/annotated-function.json): all five annotation placements on one stop.
- [PR change tour](examples/pr-change-tour.json): illustrative provenance and stale-cache behavior.

Open Neovim in this repository and run:

```vim
:TourLoad examples/annotated-function.json
```

## Annotation presentation

| Placement | Behavior |
| --- | --- |
| `above` | Wrapped virtual lines before the first target line |
| `below` | Wrapped virtual lines after the last covered line |
| `inline` | Short text at the exclusive end of the expression, shifting displayed code |
| `eol` | Short text after the last covered source line |
| `highlight` | Highlight the exact range; text is optional and is not displayed |

Main descriptions have a tour counter/title and a softer description. Notes use
a single `›` prefix with aligned continuations; short inline/EOL text uses `·`.
Notes follow the source indentation. Overflow and multiline
inline/EOL notes continue below in virtual lines. If there is too little room
for a readable first fragment, the whole note appears below.

Wrapping respects display-cell width, explicit newlines, paragraph breaks, the
configured maximum, prefixes, and available text width after number/sign columns.
Virtual lines additionally use Neovim 0.13's native overflow wrapping. When the
same buffer appears in multiple windows, wrapping uses the narrowest visible
window. Resizing reflows presentation. Code is never hard-wrapped or changed.
Horizontal scrolling can hide the short inline portion; continuation lines remain
ordinary virtual lines. Very long descriptions may require scrolling.

The active range is marked by a narrow `▎` gutter beside the line numbers. It
occupies its own statuscolumn cell, leaving every Git/diagnostic sign slot and
source highlight available. Native fold, sign, and relative/absolute number
items retain their behavior. The gutter is installed only in target windows with
the default statuscolumn; detouring away or closing restores it.

Existing custom statuscolumns are preserved. To include the tour indicator in
one, add this segment to its format (or have its provider return the segment):

```lua
"%#TourRange#%{v:lua.require'tour'.gutter()}%* "
```

`gutter()` returns `▎` for covered source lines in the rendered window, otherwise
a space. It is a cheap presentation query and does not change progress. Virtual
explanation lines have no range indicator. Changes made to a statuscolumn by the
user or another plugin during a tour are retained when closing.

Highlight defaults derive from the colorscheme:

| Group | Default |
| --- | --- |
| `TourHeader` | `Title` |
| `TourDescription` | 85% `Normal` foreground / 15% `Comment` foreground |
| `TourAnnotation` | 65% `Normal` foreground / 35% `Comment` foreground, italic |
| `TourRange` | `Title` (gutter only) |
| `TourHighlight` | `IncSearch` (explicit annotation ranges) |

Descriptions stay readable; notes use a quieter neutral color instead of a
saturated syntax accent. If a theme leaves RGB foregrounds unspecified,
descriptions fall back to `Normal` and notes to `Comment`. Defaults refresh on
`ColorScheme`; override them with `nvim_set_hl` as usual. No colors are hardcoded.

## Public v1 schema

[schema/tour.schema.json](schema/tour.schema.json) describes both input and
normalized persisted tours. Unknown fields are rejected except within `source`.
No field accepts explicit JSON `null`, except arbitrary nested `source` values.
Non-empty fields must contain a non-whitespace character. Strings outside
`source` cannot contain NUL. There are no runtime handles in the format.

| Tour field | Required / default | Meaning |
| --- | --- | --- |
| `version` | Required, exactly `1` | Format version |
| `title` | Required non-empty string | Library label |
| `steps` | Required non-empty array | Ordered conceptual stops |
| `id` | Generated if absent | 1–128 ASCII letters, digits, `_`, `-`; globally unique |
| `project_root` | Discovered if absent | Canonical absolute path after normalization |
| `current_step` | `1` | Integer in `1..#steps` |
| `completed` | `false` | Explicit completion state |
| `created_at` | Current UTC time | `YYYY-MM-DDTHH:MM:SSZ` |
| `updated_at` | `created_at` | Same UTC syntax; refreshed on save |
| `source` | Omitted | Arbitrary JSON object with provenance; never interpreted |

| Step field | Required / default | Meaning |
| --- | --- | --- |
| `title` | Required non-empty string | Concept label |
| `location` | Required object | One primary location |
| `id` | Optional non-empty string | Unique among supplied step IDs |
| `description` | Optional string | Unwrapped source explanation, may be multiline |
| `annotations` | Empty array | Zero or more notes |

A location requires `file` (non-empty path) and `range`. Optional `anchor` is a
non-empty, single-line literal substring expected on the range's **start line**.
An annotation requires `range` and `placement`. It requires non-empty `text`
unless placement is `highlight`. Annotation positions refer to the step's file;
they may be outside the primary region, but must resolve within that file.

Every range has exactly `start` and `end`; every position has exactly `line` and
`col`. **Lines are 1-based; columns are 0-based byte offsets; the end is exclusive.**
Positions must be on existing lines, on UTF-8 boundaries, with columns no greater
than that line's byte length. End must not precede start. Empty ranges are valid.
Use `{ line = next_line, col = 0 }` to exclude the next line. For the final line,
use its byte length; a one-past-EOF line is not accepted. Tabs count as one byte.

JSON Schema checks structure; the Lua validator additionally checks ordering,
unique step IDs, progress bounds, and NUL rejection. File/range availability and
UTF-8 byte boundaries are checked when resolving a step. The checked authoring
APIs validate every step before activation. Ordinary `start`/`load` allow unvisited
files to be unavailable, preserving tours for later recovery.

Project root resolution is: explicit root, nearest ancestor `.git` directory or
worktree marker file from the current working directory, then that directory.
Paths are absolute, normalized, and symlinks resolved where possible. Relative
source paths resolve against the project root, **not the JSON file's directory**.
Absolute source paths inside the root become relative; outside paths stay
absolute. Root discovery never invokes Git and never changes your working directory.

## Detours, edits, and recovery

Tour progress changes only through explicit tour navigation. Cursor moves,
buffer switches, searches, and unrelated edits never advance it. Navigation uses
the current window and leaves its layout alone. Normal Neovim rules for modified
buffers apply; enable `'hidden'` if you want to switch away from unsaved buffers.

While the active target buffer remains loaded, independent tracking extmarks
follow edits to its primary range and every annotation. Start boundaries have
right gravity and end boundaries have left gravity: insertions exactly at the
boundary stay outside the range. Undo restores mark positions. Before saving,
leaving a step, or unloading the buffer, those positions are reconciled into
semantic ranges. A wholly deleted range collapses to a valid position.

When reopening a step, literal anchor matches relocate the region and all notes
by a common row delta. Multiple matching lines choose the closest to the saved
start (earlier line wins a tie). Missing anchors fall back to valid saved ranges.
Missing anchors can be derived from nonblank start lines. Existing hints are
retained while they still match that line; edited start lines refresh the hint.
There is no fuzzy, LSP, or Treesitter recovery. Invalid files/ranges produce a
useful error and do not advance the existing tour or clear its presentation.

## Persistence and external agents

Default layout:

```text
stdpath("state")/tour.nvim/
  tours/<id>.json
  index.json
```

Tour files contain normalized schema-v1 semantic data, progress, timestamps,
completion, project root, and provenance. `index.json` is
`{ "version": 1, "projects": { "/canonical/project": "tour-id" } }`.
It records the latest activated/saved tour per project, including completed tours.
If the index is missing, invalid, or stale, resume scans valid tour files sorted
by update time (ID breaks ties). Malformed tour files are skipped with a warning.

Each write uses an exclusive temporary file in the destination directory, writes
all bytes, fsyncs, closes, and atomically renames. The tour is written before its
index; an interrupted index update cannot destroy the saved tour. With
`start`/`load`, a new tour is saved even if its first target cannot currently be
resolved. The checked authoring
variants below require whole-tour validation before saving. There is no deletion
API; remove an unwanted JSON file yourself while it is not loaded.

Progress autosaves by default. `save()`, `close()`, `finish()`, `restart()`, initial
activation, and `VimLeavePre` save even with `autosave = false`. Close saves progress
and hides UI; it never deletes data. Save source edits normally: tour persistence
stores positions and explanations, **not source buffer contents**.

An external agent only needs to write the public JSON format and tell the user:

```vim
:TourLoad /tmp/my-tour.json
```

Alternatively, another plugin can call `require('tour').start(lua_table)`.
No server, protocol, AI integration, or runtime IDs are needed. Loading a tour
with an existing ID updates it; reusing an ID from a different project is rejected.
For portable tours, omit `project_root` and load from the intended project.

## Automatic tours from coding agents

The [tour skill](skills/tour/SKILL.md) teaches any skill-enabled harness to author
and open a walkthrough through an existing Neovim MCP connection. Ask “tour me
through your changes” or “walk me through this subsystem in Neovim.” The agent
reads source revisions, resolves snippets, validates the entire tour, loads JSON
with a structured receipt, and leaves navigation to you. It uses live buffers for unsaved source and preserves edits.

Install the skill in the harness's skill directory. Its references link to the
canonical schema, example, and authoring reference in this repository. Copy with
symlinks dereferenced to make a standalone skill bundle:

```sh
cp -RL skills/tour /path/to/agent/skills/tour
```

The harness needs Neovim MCP tools that can read buffers and run Lua commands.
With a paired workspace, forward `DEV_NVIM_SOCKET` to that MCP server and supply
`DEV_WORKSPACE_ROOT` to the agent. A harness without those environment variables
can match the editor to the requested project. No provider-specific extension,
new MCP server, or API key is required by tour.nvim.

For declarative Nix installation, this flake exports `packages.<system>.tour-nvim`
and `packages.<system>.tour-skill`. Both use the same source; the skill package
includes standalone schema, example, and authoring references. `nix/package.nix`
can also be imported with `{ pkgs, src }` by configurations using this repository as a
non-flake source input. Register the skill package with each harness's own skill
catalog and install the plugin package in Neovim.

## Authoring helpers

These use the existing nvim-mcp `send_command` tool; no MCP changes are needed.
See [the authoring reference](doc/authoring.md) for complete result shapes and the
inspection-to-delivery workflow.

```lua
local tour = require("tour")
local source = tour.read_source("src/main.rs", { project_root = "/project" })
local match = tour.resolve({
  project_root = "/project",
  file = "src/main.rs",
  snippet = "Config::new(&args)",
  revision = source.revision,
  -- within = enclosing_range,
})
-- On success, use match.range in a step or annotation.
-- Ambiguous matches return candidate ranges; none is selected automatically.

local opts = { revisions = { [source.file] = source.revision } }
local checked = tour.validate(data, opts)
-- { ok, errors, revisions, data? }; checks every step and annotation.
local receipt = tour.load_checked("/tmp/my-tour.json", opts)
-- Or tour.start_checked(data, opts).
-- { ok, id, title, current_step, step_count, persisted, displayed, errors }
```

Check `ok` before using a result's fields. `read_source` returns unnumbered lines
and, for loaded buffers, `bufnr`, `modified`, and `changedtick`. Unsaved edits take
precedence over disk. Revisions are content digests; keep them separate from the
saved tour. `validate`, `resolve`, and `read_source` neither initialize presentation
nor load buffers, move the cursor, write storage, or modify their inputs.

Validation collects schema and live range errors across the whole tour, with
file, step/annotation indices, field paths, rejected ranges, and valid bounds as
applicable. Successful validation returns normalized data with anchor relocation
applied. Snippets may be multiline; the helper calculates byte columns and
rejects ambiguity. Symbols remain an optional aid in the agent's existing tools,
not a dependency or replacement for persisted ranges.

Checked loading rejects validation failures and stale inspection revisions before
saving or replacing the active tour. It checks again after source-opening hooks.
On later I/O/rendering failure, a saved file or partial UI may exist: inspect the
receipt. `persisted` is true for confirmed tour/index writes, false before a save
attempt, or JSON null for an unconfirmed write. `displayed` confirms rendering.

The bridge still wraps output in a string. Retrieve a consistent JSON result with:

```vim
lua print(vim.json.encode(require("tour").load_checked("/tmp/my-tour.json")))
```

Pass inspection revisions as the second argument to detect edits since authoring;
the [skill](skills/tour/SKILL.md) demonstrates a separate options JSON file. Report
success only when `ok`, `persisted`, and `displayed` are all true. Existing `load`,
`start`, and `:TourLoad` retain their recovery semantics and return/raise behavior.

## Development

The locked flake uses nixpkgs plus the Neovim nightly overlay because the pinned
nixpkgs snapshot packages 0.12. It pins Neovim **0.13.0-nightly+e884c01**. The dev
shell provides that editor, LuaLS, StyLua, Selene, Git, check-jsonschema, nixfmt,
Actionlint, and Gitleaks.

```sh
direnv allow
nix develop --command stylua lua plugin tests examples
nix develop --command selene lua plugin tests examples
nix develop --command nixfmt --check flake.nix nix/package.nix
nix develop --command nvim --headless -u NONE -i NONE -l tests/run.lua
nix develop --command bash -c 'check-jsonschema --schemafile schema/tour.schema.json examples/*.json'
nix flake check --print-build-logs
nix build .#tour-nvim .#tour-skill --no-link
```

Use `path:.` as the flake reference for an untracked local checkout. The native
headless harness includes persistence fault injection, a separate Neovim process
for exit recovery, annotation/namespace inspection, edit tracking, example loads,
and the step-three detour/save/reset/resume contract. `flake check` runs formatting,
linting, schema validation, workflow validation, secret scanning, and the complete
headless suite. GitHub Actions also scans full Git history and builds both packages. See
[doc/api-notes.md](doc/api-notes.md) for the locally inspected 0.13 API details.

Implementation ownership is deliberately small: `model` validates/copies data,
`project` and `position` normalize coordinates, `storage` owns JSON, `source`
reads immutable snapshots, `author` resolves snippets and validates live locations,
`location` shares pure anchor relocation with navigation, `session` owns the
single loaded tour, and `render` owns two namespaces. `init` and `commands` expose the public entry points. Wrapping is an
isolated utility. There is no event bus, editor abstraction, or compatibility layer.

V1 intentionally has one loaded tour at a time, buffer-wide presentation, and
literal row-based relocation. It does not track inactive steps through arbitrary
edits, synchronize concurrent Neovim writers (last writer wins), guarantee
power-loss durability of directory metadata, or semantically recover rewritten
code. Long descriptions may exceed a viewport. These limits do not affect the
separation between editor position and conceptual tour progress.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development conventions and reporting
bugs. [SECURITY.md](SECURITY.md) covers vulnerability reports and the privacy of
saved tours. No telemetry or network calls are made by the plugin itself.

Distributed under the [MIT license](LICENSE).
