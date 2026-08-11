# impostor-pkg.nvim — Design Spec

Date: 2026-08-11

## Purpose

A standalone Neovim plugin (`johnkingkong/impostor-pkg.nvim`) that flags
malicious, typosquatted, or otherwise risky npm/yarn/pnpm packages — the
Neovim equivalent of WebStorm's package risk warnings. It is the first of two
related "package guard" plugins; the second (scanning lazy.nvim plugins
themselves) is a separate design/spec/repo.

Once this plugin exists, the `johnkingkong/nvim-config` repo only needs a thin
`lua/plugins/impostor-pkg.lua` spec pointing at it, following the same pattern
as `claude-reviewer.lua` and `globular-telescope.lua`.

## Non-goals (v1)

- Monorepo/workspace aggregation across multiple `package.json` files — v1 scans
  the single project root (nearest lockfile + `package.json` to cwd).
- Blocking or intercepting install commands before they run — detection is
  post-install (lockfile-triggered) or on-demand, never preventative.
- Any backend beyond Socket CLI and the native package manager's `audit`
  subcommand.

## Architecture

Six independently testable Lua modules:

- **`detect.lua`** — finds the project root and which lockfile is present
  (`package-lock.json` / `yarn.lock` / `pnpm-lock.yaml`), and thus which package
  manager (npm/yarn/pnpm) is in play.
- **`backends/socket.lua`** — checks whether the `socket` CLI is installed *and*
  authenticated (a token is configured), builds the scan/score command, and
  parses its JSON output into the common `Finding` shape.
- **`backends/audit.lua`** — runs `npm audit --json`, `yarn audit --json`, or
  `pnpm audit --json` matching the detected package manager, and parses the
  result into the same `Finding` shape.
- **`scanner.lua`** — orchestrator. Picks Socket if available, else falls back
  to audit. Runs the chosen backend asynchronously (`vim.system`, non-blocking).
  Hashes the lockfile contents and skips re-scanning if unchanged since the
  last run (the manual command bypasses this cache).
- **`diagnostics.lua`** — maps each finding's package name to its line under
  `dependencies`/`devDependencies` in `package.json` and applies
  `vim.diagnostic` (virtual text + sign) under a dedicated namespace.
- **`ui.lua`** — one-line `vim.notify` summary (e.g. "3 packages flagged: 1
  high, 2 low") plus a dismissible floating window listing name / severity /
  backend / reason per finding; `<CR>` on an entry jumps to its diagnostic line.

`init.lua` wires these together: `setup(opts)`, an autocmd on lockfile
`BufWritePost`, and the `:ImpostorCheck` command (alias `:Impostor`).

### Common `Finding` shape

```lua
{ name = "left-pad", version = "1.3.0", severity = "high",
  backend = "socket" | "audit", reason = "..." }
```

## Data flow

1. On `setup()`, `scanner.lua` probes once whether Socket is installed and
   logged in (token configured). If not, `vim.notify` fires **once** at
   startup: "impostor-pkg: Socket CLI not configured — using npm/yarn/pnpm
   audit only. Run `socket login` anytime to enable full malicious-package
   detection." The plugin is never disabled by this — it just runs in
   audit-only mode until Socket is configured.
2. Trigger: `BufWritePost` on a lockfile, or the `:ImpostorCheck` command run
   manually.
3. `scanner.lua` hashes the lockfile; if the hash is unchanged since the last
   scan, it skips (the manual command always bypasses this cache).
4. Runs the chosen backend async, parses output into `Finding[]`.
5. Results fan out to `ui.lua` (notify + floating window) and
   `diagnostics.lua` (marks in the open `package.json` buffer, if any).

## Detection backends

- **Primary: Socket CLI** (`@socketsecurity/cli`, binary `socket`). Real
  malicious-package / typosquat / protestware detection — the actual
  equivalent of WebStorm's feature. Requires the user to have installed the
  CLI and run `socket login` (API token) at least once; there is no reliable
  token-free path (confirmed via docs.socket.dev — most commands require a
  token from the Socket dashboard).
- **Fallback: native audit** (`npm audit` / `yarn audit` / `pnpm audit`,
  whichever matches the detected lockfile). Zero extra install. Only surfaces
  known-CVE registry advisories, not malicious/typosquat packages — a weaker
  signal, but a workable zero-config default.

## Config (`setup(opts)`)

```lua
{
  backend = "auto",       -- "auto" | "socket" | "audit"
  auto_scan_on_save = true,
  ignore = {},            -- package names to always suppress (false-positive allowlist)
  min_severity = "low",   -- "low" | "moderate" | "high" | "critical"
}
```

## Error handling

- Neither `socket` nor the project's package manager CLI is on `PATH` → one
  warning notify, the command becomes a no-op.
- CLI crashes, times out, or returns unparseable JSON → warning notify with
  the raw error; previously-set diagnostics are left untouched (no crash, no
  silent wipe).
- No lockfile found in the project root → informational notify, no-op.

## Testing

Plenary/busted-style specs per module. The actual `socket` / `npm` / `yarn` /
`pnpm` CLIs are always mocked — tests never hit the network or a real CLI.
Coverage:

- `detect.lua`: package-manager detection from fixture directory trees.
- `backends/socket.lua`, `backends/audit.lua`: JSON-to-`Finding` parsing,
  including malformed/unexpected input.
- `scanner.lua`: lockfile-hash cache behavior (skip vs. re-scan).
- `diagnostics.lua`: package-name-to-line mapping against `package.json`
  fixtures.

## Naming

Plugin repo: `impostor-pkg.nvim`. Commands: `:ImpostorCheck` (primary),
`:Impostor` (alias).
