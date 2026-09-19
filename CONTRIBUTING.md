# Contributing

Small, focused bug fixes, documentation improvements, and tests are welcome.
For substantial behavior or schema changes, open an issue first so the design
can be discussed before implementation.

## Scope

tour.nvim presents durable tours beside actual source code. It targets Neovim
0.13 only and has no runtime dependencies. Keep generation, AI providers, Git/PR
fetching, semantic indexing, and editor orchestration in external tools.

Preserve these contracts:

- Tour progress changes only through explicit navigation. Detours are ordinary
  editor use and must not affect the conceptual step.
- Persist semantic data, never buffer/window/extmark IDs or source revisions.
- Keep explanations virtual and clear plugin-owned presentation on close.
- Preserve other plugins' signs, custom statuscolumns, and the user's layout.
- Validate external input with contextual errors and preserve recoverable tours.
- Keep public positions 1-based lines, 0-based byte columns, and exclusive ends.

## Development

The locked Nix flake supplies the tested Neovim 0.13 build and development tools:

```sh
nix develop
stylua lua plugin tests examples
nixfmt flake.nix nix/package.nix
selene lua plugin tests examples
nvim --headless -u NONE -i NONE -l tests/run.lua
check-jsonschema --schemafile schema/tour.schema.json examples/*.json
nix flake check --print-build-logs
nix build .#tour-nvim .#tour-skill --no-link
```

`direnv allow` is an alternative to `nix develop`. Without Nix, install Neovim
0.13, StyLua, Selene, and check-jsonschema and run the corresponding commands.
Nix remains the reproducible CI environment. New files must be visible to Git
for Git-backed flake evaluation; `git add -N path/to/new-file` is sufficient.

The native headless suite exercises the public API, actual Neovim extmarks,
source edits, persistence failures, and detour/resume behavior. Add regression
coverage for changed behavior. Test all bundled JSON examples when changing the
schema or location rules. Inspect the installed 0.13 help before adopting a new
rendering API; there are no compatibility branches for older versions.

## Pull requests

Explain the problem, the resulting behavior, and the checks you ran. Keep
unrelated changes separate. Update README/help and the JSON Schema when changing
public behavior. Update the authoring reference when changing agent helpers;
the bundled skill references that same document through a relative symlink.

Use synthetic source in fixtures and reports. Do not attach saved tours from
private projects without reviewing their descriptions, anchors, source metadata,
and absolute paths. Use a public no-reply Git email if you want to keep your
personal address out of commit history.

## Repository checks

CI runs the locked flake checks and builds both deliverables. Actionlint validates
the workflow; Gitleaks scans repository files and full Git history with redacted
output. To repeat the history scan locally:

```sh
nix develop --command gitleaks git --redact --no-banner --log-opts=--all .
```

Secret scanning is a guard, not proof that arbitrary prose is safe to publish.
Review files and commit metadata before pushing. Do not add broad scanner
allowlists to hide a finding.

Contributions are distributed under the repository's [MIT license](LICENSE).
