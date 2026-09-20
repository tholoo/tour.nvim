# Authoring tours from inspected source

These helpers are available on `require("tour")` in Neovim 0.13. They need no
MCP extension or symbol provider. The durable format remains schema v1: concrete
byte ranges and optional literal anchors. All examples below use real source
paths and snippets chosen by the caller.

## Read, resolve, validate, then load

```lua
local tour = require("tour")
local source = tour.read_source("src/main.rs", { project_root = "/project" })
assert(source.ok, vim.inspect(source.errors))

local match = tour.resolve({
  project_root = "/project",
  file = "src/main.rs",
  snippet = "Config::new(&args)",
  revision = source.revision,
  -- within = enclosing_function_range, -- optional, with the same position rules
})
assert(match.ok, vim.inspect(match.errors))

local data = {
  version = 1,
  title = "Configuration flow",
  project_root = "/project",
  steps = {
    { title = "Parse configuration", location = { file = "src/main.rs", range = match.range } },
  },
}
local opts = { revisions = { [source.file] = source.revision } }
local check = tour.validate(data, opts)
if check.ok then
  local receipt = tour.start_checked(check.data, opts)
  print(vim.json.encode(receipt))
else
  print(vim.json.encode(check))
end
```

`read_source`, `resolve`, and `validate` do not initialize a session, create or
load buffers, trigger read autocmds, move the cursor, reconcile active tracking
marks, write storage, or change their inputs. Expected failures return
`{ ok = false, errors = { ... } }`. Successful results and arrays are detached
copies. Empty error/candidate lists encode as JSON arrays.

### `read_source(file, { project_root? })`

Returns `{ ok, file, lines, origin, revision, bufnr?, modified?, changedtick? }`.
`file` is canonical and absolute. `lines` is an array of raw strings without line
number prefixes. A loaded buffer takes precedence over disk, including unsaved
edits and buffers whose files have been deleted. `origin` is `buffer` or `disk`;
buffer metadata is absent for disk reads. Empty files have one empty line.

Unloaded files are read as UTF-8 text, with an initial UTF-8 BOM and CRLF line
endings normalized. No encoding conversion or read autocmds run; load unusual
encodings in Neovim first. Sources containing NUL bytes are rejected.

`revision` is an opaque digest of the logical line array. It is independent of
buffer IDs, changedticks, final newline presence, and disk-vs-buffer origin.
Identical content has the same revision, including after an edit is undone.
This detects content changes, not editing activity. The optional buffer metadata
is for inspection only; it must never be added to saved tour data.

### `resolve({ file, snippet, project_root?, within?, revision? })`

Searches literal text, not patterns. A non-empty snippet may span multiple lines;
use LF between lines, even for a CRLF file. Positions use 1-based lines, 0-based
UTF-8 byte columns, and exclusive ends. Optional `within` restricts the entire
match to that range. Optional `revision` rejects source changed since inspection.

One match returns `{ ok = true, file, range, revision }`. No matches return
`snippet_not_found`; multiple matches return `ambiguous_snippet`. Both include
`file`, `revision`, and `candidates` (an array of ranges). Overlapping occurrences
count separately. Narrow `within` or provide more context; the helper never picks
an occurrence silently. Existing anchor *recovery* still chooses the nearest
saved position, because recovery and authoring serve different purposes.

Symbols found through another tool can supply a surrounding `within` range.
No symbol selector, LSP dependency, or semantic indexing is introduced.

### `validate(data, { revisions? })`

Checks tour structure and every primary/annotation range against source. Loaded
buffers are authoritative. Each distinct file is read once per validation.
Returns `{ ok, errors, revisions, data? }`. `data` is present only on success and
contains a normalized, detached tour with anchor relocation applied and missing
anchors derived. Both primary and annotation ranges use the same relocation
rules as navigation. Input data is never rewritten.

Independent schema errors and live range failures are collected together. A
malformed container or endpoint is reported without guessing missing values;
other steps and valid ranges still get checked. Errors include the fields that
apply: `code`, `message`, `path`, `file`, `step`, `annotation`, `range`, and `bounds`.
Step/annotation indices are 1-based; source files are canonical absolute paths.
A rejected range is the range *after* relocation. Bounds contain `min_line`,
`max_line`, `min_col`, and `max_col` (the last only when that endpoint's line
exists). UTF-8 continuation-byte offsets are rejected even within those bounds.

`revisions` maps canonical source paths to current content digests. Pass an
inspection-time map as `opts.revisions` to detect stale authoring. Input keys may
also be project-relative. Additional inspected files in the map are checked even
if no step references them. A stale error includes `expected_revision` and
`actual_revision`. Do not replace old inspection revisions with fresh ones merely
to bypass a failure; reread the changed source and repair the tour.

### `start_checked(data, { revisions? })` / `load_checked(path, { revisions? })`

Validate every step before activation. `load_checked` reads ordinary v1 JSON;
relative source paths resolve from its project root, not the JSON directory.
Optional revision expectations remain separate from that JSON.

Successful activation returns:

```json
{
  "ok": true,
  "id": "stable-tour-id",
  "title": "Configuration flow",
  "current_step": 1,
  "step_count": 4,
  "persisted": true,
  "displayed": true,
  "errors": []
}
```

Validation/revision failures return `ok = false`, `persisted = false`,
`displayed = false`, and all errors. They do not save the new tour or replace the
active one. The target is then opened normally; revisions are checked again after
read/enter hooks and before saving or replacing presentation. Hooks may themselves
have changed editor state, so this later failure does not promise to undo them.

For activation or I/O failures, inspect the receipt rather than assuming rollback.
`persisted = true` confirms both tour and index writes; `false` means no new-tour
save was attempted; JSON `null` means an attempted write was not confirmed and a
recoverable file may exist. `displayed = true` confirms rendering finished;
`false` means it was not confirmed (a rendering failure may leave partial UI).
ID/title/progress fields are included once preflight has succeeded. A receipt is
not a filesystem transaction: source files can still change after inspection,
and tour and index writes are individually atomic.

Existing `start`, `load`, and `:TourLoad` retain their recovery behavior: they
save structurally valid tours even when source is currently unavailable and check
locations as they are visited. Use the checked variants for agent delivery.

Error codes: `invalid_request`, `invalid_schema`, `unreadable_file`,
`unsupported_source`, `invalid_range`, `stale_source`, `snippet_not_found`,
`ambiguous_snippet`, `invalid_json`, `persistence_failed`, `activation_failed`.
Consumers should branch on `code`, not parse `message` wording.

## MCP transport

The Lua helpers and skill do not install MCP tools. Discover the tools provided
by the connected bridge: some integrations add structured tools, while ordinary
nvim-mcp command tools remain sufficient. Source inspection, snippet resolution,
and separate validation can still call the Lua helpers through `send_command`.

### Optional structured integrations

A bridge may expose a structured wrapper for `tour.load_checked`. Discover its
advertised tool schema rather than assuming a particular tool name or argument
shape. Pass the tour JSON path and original inspection revisions so the wrapper
can call `tour.load_checked(path, { revisions = revisions })` and return its
receipt directly, for example as MCP `structuredContent`.

Check `ok`, `persisted`, and `displayed`; all must be true before reporting
success. Keep the receipt's ID and progress fields for confirmation. A transport
error means completion is unknown, not that nothing was saved. Mutating load
requests must not be automatically replayed after a lost response; inspect the
editor and saved tour before deciding to retry. A validation or stale-source
error is not a reason to bypass checked loading via another transport.

For machine-readable source inspection, `tour.read_source` already returns raw
line arrays and, for loaded buffers, buffer ID, modified state, and changedtick.
Compare buffer ID and changedtick only within the same editor session; use the
content revision, not those editor handles, to guard checked tour loading.
No structured bridge extension is required by the plugin or the portable skill.

### Command-based fallback

When no suitable structured wrapper is available, use `send_command` for
delivery. For source inspection through this transport:

```vim
lua print(vim.json.encode(require("tour").read_source("src/main.rs", { project_root = "/project" })))
```

For delivery, put the ordinary v1 tour in a unique temporary JSON file. Keep
revision expectations in a separate temporary JSON file shaped like
`{ "revisions": { "/project/src/main.rs": "<revision from inspection>" } }`:

```vim
lua local opts = vim.json.decode(table.concat(vim.fn.readfile("/tmp/unique-tour-options.json"), "\n")); print(vim.json.encode(require("tour").load_checked("/tmp/unique-tour.json", opts)))
```

Escape actual paths as Lua string literals. The bridge still transports command
output as a string; parse the printed JSON object and inspect `ok`, `persisted`,
and `displayed`. This command-based transport does not provide a native
structured receipt. Plugin/connection errors can still be reported by the bridge
itself.
Keep runtime metadata and revision maps out of the saved v1 tour. Remove only
agent-created temporary files after confirmed successful delivery.
