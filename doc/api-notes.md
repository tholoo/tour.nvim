# Local Neovim 0.13 API inspection

Rendering was implemented after inspecting the installed
`NVIM v0.13.0-nightly+e884c01` runtime help. The flake pins the same upstream commit.
No rendering compatibility branches exist.

- `:help nvim_buf_set_extmark()` (`api.txt`, lines 3270–3425 in this build):
  zero-based rows and byte columns; `end_col` is exclusive. `virt_text_pos =
  "inline"` shifts displayed buffer text and `"eol"` attaches after EOL.
- `virt_lines` and `virt_lines_above` place multiline explanations outside source
  contents. This build supports `virt_lines_overflow = "wrap"` independent of
  `'wrap'`. The plugin also wraps explicitly to respect its configured maximum
  width and prefixes.
- `number_hl_group` was verified but the active range now uses a dedicated
  statuscolumn cell. `hl_group` with end positions highlights explicit annotation
  ranges only.
- `:help 'statuscolumn'` (`options.txt`, lines 6379–6438): native `%C`, `%s`, and
  `%l` retain folds, signs, and number/relativenumber behavior. `v:lnum` and
  `v:virtnum` identify the drawn source/virtual line. Expressions evaluate in the
  rendered window's context. Existing custom formats are preserved.
- `:help sign-priority`: signs exceeding available slots hide lower-priority
  signs, so the tour gutter uses a separate statuscolumn cell rather than signs.
  `nvim__redraw({ statuscolumn = true })` invalidates the column after updates.
- `right_gravity` defaults true, `end_right_gravity` defaults false. Both are
  explicit for tracking ranges, with `undo_restore = true`. Insertions at the
  start push the start forward; insertions at the end remain outside the range.
- `nvim_buf_get_extmark_by_id(..., { details = true })` returns moving start/end
  coordinates. Tracking and presentation use separate plugin-owned namespaces.
- `:help vim.fs.root()` accepts `.git` as either a directory or worktree marker
  file; `vim.fs.abspath`, `vim.fs.normalize`, and `vim.uv.fs_realpath` support
  canonical paths without invoking Git.
- `vim.uv.fs_open/write/fsync/close/rename` supply atomic file replacement;
  `vim.json.encode/decode` supply the durable interchange format.
- Source inspection uses `nvim_buf_get_lines` with strict bounds and
  `nvim_buf_get_changedtick` (`api.txt`, lines 2576–2633), plus the buffer-local
  `modified` flag. Unloaded buffers are not read through that API (they return no
  lines); plain file I/O avoids buffer creation and read autocmds. `:help readfile()`
  documents BOM/CRLF/final-newline behavior and recommends Lua file I/O; snapshots
  normalize UTF-8 disk text to logical lines before hashing. No runtime buffer
  metadata participates in persisted tours.

Tests cover actual extmark details and boundary movement in this exact build,
not mocks of the Neovim rendering APIs.
