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
- `number_hl_group` highlights existing number columns without installing signs
  or changing `'signcolumn'`. `hl_group` with end positions highlights ranges.
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

Tests cover actual extmark details and boundary movement in this exact build,
not mocks of the Neovim rendering APIs.
