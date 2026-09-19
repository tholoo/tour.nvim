# Security and privacy

Security fixes target the current `main` branch on Neovim 0.13. There are no
maintained older release lines yet.

## Reporting a vulnerability

Use the repository's **Security → Report a vulnerability** option when private
reporting is enabled. Include a minimal synthetic reproduction, the affected
revision, Neovim version, and the impact you observed. Do not post credentials,
private code, or sensitive saved tours in a public issue.

If private reporting is unavailable, open an issue requesting a private contact
method without disclosing vulnerability details or sensitive data.

## Data handling

The plugin does not make network requests, call AI services, or execute tour
text as Lua or Ex commands. Normal Neovim behavior still applies when opening a
source file, including user-configured autocommands. Tour files can name absolute
paths outside the project; project roots are a path-resolution convention, not a
filesystem sandbox. Review tours from sources you do not trust before opening.

Saved tours live under `stdpath("state")/tour.nvim` by default. They can contain
absolute project roots, paths, literal source anchors, descriptions, and arbitrary
provenance metadata. Those fields may reveal private information even though
runtime handles are never persisted. Review and redact exported tours before
sharing them. Saving a tour does not save modified source buffers.

Agent integrations and MCP connections belong to the calling harness. Review
that harness's access independently; tour.nvim does not authenticate editor
connections or manage provider credentials.
