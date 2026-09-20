---
name: tour
description: Create and open a durable tour.nvim walkthrough in the user's Neovim session when asked to tour code, walk through changes, or explain a subsystem in the editor. Use existing Neovim MCP tools for delivery.
---

# Create a code tour

Turn the requested explanation into conceptual stops beside the actual source,
then open the saved walkthrough in the user's paired Neovim session.

## Connect and inspect

Discover the existing Neovim MCP tools (`connect`, `get_state`, buffer readers,
`send_command`). If the bridge offers structured tools, inspect their schemas
before using them; tour.nvim itself installs no MCP tools.
Use `DEV_NVIM_SOCKET` when supplied; it identifies the editor paired with this
workspace. If that editor is unavailable, report the connection
failure rather than choosing another instance. Without a binding, match the
editor to the requested project; clarify only if several instances still match.

Inspect editor state and confirm `require("tour")` is available through
`send_command`. Use `DEV_WORKSPACE_ROOT` when supplied as the explicit
`project_root`; otherwise determine the requested project's canonical root.
The user's current buffer can be an unrelated detour.

Read [the authoring interface](references/authoring.md) before inspecting source
or delivering a tour. Call `require("tour").read_source(file, { project_root = root })`
through `send_command` and print its result with `vim.json.encode`. It returns raw
line arrays, a content revision, and metadata for loaded buffers; unsaved edits
take precedence over disk. Keep each inspected file's revision for delivery.
Prefer these raw lines over numbered display text when calculating byte ranges.
Compare buffer ID and changedtick only within the same editor session; neither
is a substitute for `read_source` content revisions during checked loading.
Preserve the user's source and saved/unsaved state while explaining it.

## Author the data

Read [the v1 schema](references/tour.schema.json). For the shape of a function with
several annotations, consult [the example](references/annotated-function.json).
Use paths and positions from the actual project, not the example's fixture paths.

- Order steps by the requested explanation: behavior, control flow, or the
  reasons for a change. One function with several interesting expressions usually
  needs one step with several annotations.
- Give each step an unnumbered title (tour.nvim displays the step counter),
  primary range, and description explaining what the
  reader is looking at and why it matters. Keep incidental details in annotations.
- Highlight **every source line the user is expected to read for this step** with
  explicit `placement: "highlight"` annotations. The primary range marks the
  gutter only; it and text annotations are not substitutes for highlighting.
  Cover the full relevant line text, from column 0 through the final line's byte
  length. Use separate highlight ranges for noncontiguous reading, leaving
  unrelated code unhighlighted; code in another file needs its own step.
  Before delivery, check the description and notes against the highlight ranges:
  every line needed to follow the explanation must be covered, not just the
  function signature, anchor, or first line of a block.
- Positions use **1-based lines, 0-based byte columns, exclusive ends**. Count
  UTF-8 bytes, not characters; tabs occupy one byte. Both endpoints must exist in
  the source. End-of-file is the final line's byte length, not another line.
- Set `project_root` explicitly and prefer project-relative source paths. Each
  annotation refers to its step's file and may lie outside the primary range.
- Use a distinctive literal substring from the primary range's **start line** as
  its anchor. Multiline anchors and anchors from another line are invalid hints.
- Choose `above`/`below` for longer notes, `inline`/`eol` for short details, and
  `highlight` for emphasis without text. Descriptions and notes remain unwrapped
  in JSON; tour.nvim handles display wrapping.
- Supply `version = 1`. Start a new tour with a fresh ID, retaining it when fixing
  that same tour. Omit timestamps and progress fields to use plugin defaults.
  Provenance is optional JSON metadata; generate only the requested explanation.

Use `tour.resolve({ file, snippet, project_root, revision, within? })` for literal
single-line or multiline snippets instead of manually counting columns. A unique
match returns the byte range. If ambiguous, narrow the surrounding range or add
literal context; do not silently choose a candidate. Symbols from existing tools
may help find an enclosing range, but saved locations remain ordinary v1 ranges.

Use `tour.validate(data, { revisions = inspected_revisions })` when a separate
preflight is useful; it returns all schema/location errors without changing the
editor or saving the tour. Checked loading also performs this validation.

## Deliver through the existing editor connection

Write the v1 tour as UTF-8 JSON in a uniquely named temporary file on the editor's
filesystem, outside the project unless the user requested a checked-in tour.
The agent and editor in a `dev` workspace share that filesystem.

If the bridge offers a structured wrapper for `tour.load_checked`, use its
advertised schema to pass the tour path and original inspection revisions. Read
the returned receipt directly. Tool names and argument shapes belong to the
bridge; do not assume a particular wrapper exists.

Otherwise use the standard `send_command` workflow. Write a separate temporary
options JSON containing
`{ "revisions": { "/absolute/source/path": "revision-from-inspection" } }`.
Call `load_checked`, with actual paths substituted as escaped Lua string literals:

```lua
lua local opts = vim.json.decode(table.concat(vim.fn.readfile("/tmp/unique-tour-options.json"), "\n")); print(vim.json.encode(require("tour").load_checked("/tmp/unique-tour.json", opts)))
```

Parse the JSON receipt from MCP's command output. With either transport, report
success only when `ok`, `persisted`, and `displayed` are all true, and confirm its
`id`, `current_step`, and `step_count`. Transport failures mean completion is
unknown; inspect the editor and saved tour before deciding to retry. A validation
or stale-source error is not a reason to bypass checked loading or revision checks
via another transport.

On `stale_source`, reread changed files and repair affected locations before
retrying. Do not refresh revision tokens solely to bypass the check. On schema or
range errors, use the reported step, annotation, file, and bounds to repair all
failures together; retain the same tour ID. Preflight failures do not save a new
tour or replace the active presentation. An I/O or activation failure may leave
a saved tour; inspect `persisted` (null means unconfirmed) and `displayed`.

If the plugin/editor is unavailable or a repeated error remains unresolved,
preserve the temporary files and report the blocker and paths. After confirmed
success, remove only the temporary files you created; tour.nvim owns the saved
copy. Leave navigation to the user unless they requested guided advancement.

Tell the user the title and number of steps, and mention `:TourNext`, `:TourPrev`,
and `:TourOverview`. `:TourClose` saves and hides it; `:TourResume` reconstructs it
later. Detours never change conceptual tour progress.
