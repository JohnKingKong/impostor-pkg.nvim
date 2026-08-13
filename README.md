# **impostor-pkg.nvim**

Flags malicious, typosquatted, or otherwise risky npm/yarn/pnpm packages — both already installed and *before* you install them — the Neovim equivalent of WebStorm's package risk warnings.

## Why this exists

`npm audit` (and friends) only tells you about a dependency after it's already resolved into your lockfile — by then the install already ran. There's no native Neovim equivalent of WebStorm's inline package risk warnings, for packages you already have *or* ones you're about to add.

**`impostor-pkg.nvim` covers both directions.** It scans your already-locked dependencies for known vulnerabilities (post-install), and separately diffs `package.json` against the lockfile to catch anything newly declared but not yet installed (pre-install) — so a risky package can be flagged, and its install stopped, before it ever touches `node_modules`.

Uses [Socket CLI](https://docs.socket.dev/docs/socket-cli) when it's installed and authenticated (`socket login`) for real malicious-package detection, and falls back to the project's native `npm audit` / `yarn audit` / `pnpm audit` otherwise.

---

## How it works

1. On `package-lock.json`/`yarn.lock`/`pnpm-lock.yaml` save, or once on startup, your **already-installed** dependencies are scanned via Socket (if configured) or your package manager's native audit — flagged packages get a notify summary, a floating results window, and inline diagnostics on `package.json`.
2. On `package.json` save (debounced ~500ms), or once on startup, declared dependencies are separately diffed against the lockfile to find anything **not yet installed**, and only those are checked — via Socket, or (audit-only) by resolving the lockfile over the network without touching `node_modules`, auditing, then restoring the lockfile to its exact original contents.
3. `:ImpostorCheck` (alias `:Impostor`) forces a fresh post-install scan on demand, bypassing the lockfile-hash cache.
4. `:ImpostorInstall` checks pending dependencies, then runs your project's actual package manager's install (`npm`/`yarn`/`pnpm`) in a terminal split. If anything is flagged at or above `confirm_threshold`, or couldn't be verified at all (yarn has no lockfile-only resolve mode, so it needs Socket to check pending deps), you're asked to confirm before it proceeds.

**A passive scan never installs anything or leaves your lockfile changed** — resolving it to see what a pending dependency would look like is an internal detection step, immediately reverted. Only accepting `:ImpostorInstall`'s confirm prompt runs a real install.

**Only one scan runs at a time.** The passive autocmd and `:ImpostorInstall` both funnel through the same queue, so a manual install invoked while a background scan is still resolving waits its turn instead of racing it on the same files.

**Diagnostics survive however you open `package.json`** — even `nvim .` into a file explorer, where a scan can finish before the file is ever opened. The last result is cached per project and reapplied the instant its buffer actually loads, no re-scan needed.

**If Socket isn't installed or authenticated**, you'll see a one-time startup notice and everything falls back to audit-only mode — the plugin is never disabled by this.

---

## Installation

> **Requirements:** Neovim >= 0.10, and the relevant package manager (`npm`, `yarn`, or `pnpm`) on your `$PATH`. Optional: [Socket CLI](https://docs.socket.dev/docs/socket-cli) (`npm i -g @socketsecurity/cli`, then `socket login`) for full malicious-package detection.

> **Important:** Use `lazy = false`. `auto_scan_on_startup` scans once on `VimEnter` — if the plugin is lazy-loaded via `event`/`cmd`, it won't be loaded in time to register that autocmd for the current session.

### lazy.nvim

```lua
{
  "johnkingkong/impostor-pkg.nvim",
  lazy = false,
  config = function()
    require("impostor-pkg").setup({
      -- see Configuration below
    })
  end,
}
```

### vim-plug

```vim
Plug 'johnkingkong/impostor-pkg.nvim'
```

```lua
require('impostor-pkg').setup()
```

### pckr.nvim

```lua
require('pckr').add({
  {
    'johnkingkong/impostor-pkg.nvim',
    config = function()
      require('impostor-pkg').setup()
    end
  };
})
```

### mini.deps

```lua
local MiniDeps = require('mini.deps')
MiniDeps.add({ source = 'johnkingkong/impostor-pkg.nvim' })
require('impostor-pkg').setup()
```

---

## Configuration

```lua
require("impostor-pkg").setup({
  backend = "auto",                       -- "auto" | "socket" | "audit"
  auto_scan_on_save = true,               -- scan on lockfile save (post-install)
  auto_scan_on_package_json_save = true,  -- scan on package.json save (pre-install)
  auto_scan_on_startup = true,            -- scan once on VimEnter (both directions)
  confirm_threshold = "high",             -- "low" | "moderate" | "high" | "critical" — severity that gates :ImpostorInstall
  ignore = {},                            -- package names to always suppress
  min_severity = "low",                   -- "low" | "moderate" | "high" | "critical"
})
```

`setup()` is entirely optional — skip it and the plugin runs with the defaults above.

Commands: `:ImpostorCheck` / `:Impostor` (manual post-install scan), `:ImpostorInstall` (check pending deps, then install).

---

## Architecture

The plugin is split into small, single-purpose modules:

**`lua/impostor-pkg/init.lua`** — the public API: `setup()`, `check()`, `check_preinstall()`, `install()`; wires the `BufWritePost`/`VimEnter`/`BufReadPost` autocmds and the passive-scan debounce/serialization

**`lua/impostor-pkg/config.lua`** — defaults, option validation, `setup()`/`get()`

**`lua/impostor-pkg/detect.lua`** — finds the project root and package manager from the nearest lockfile up from cwd

**`lua/impostor-pkg/preinstall.lua`** — diffs `package.json`'s declared dependencies against the lockfile to find ones not yet installed

**`lua/impostor-pkg/scanner.lua`** — orchestrates post-install (`run`) and pre-install (`run_preinstall`) scans: backend selection, lockfile-hash caching, and the snapshot/restore around a detection-only lockfile resolve

**`lua/impostor-pkg/backends/socket.lua`** — Socket CLI availability check, scan command, and result parsing

**`lua/impostor-pkg/backends/audit.lua`** — native `npm`/`yarn`/`pnpm audit` commands, `--package-lock-only`/`--lockfile-only` resolution, and result parsing

**`lua/impostor-pkg/diagnostics.lua`** — maps findings to their line in `package.json` and applies `vim.diagnostic`

**`lua/impostor-pkg/ui.lua`** — `vim.notify` summaries and the floating results window

**`plugin/impostor-pkg.lua`** — registers `:ImpostorCheck`, `:Impostor`, `:ImpostorInstall`

**`lua/health/impostor-pkg.lua`** — powers `:checkhealth impostor-pkg`

---

## Health check

Run `:checkhealth impostor-pkg` to verify a package manager and (optionally) Socket CLI are available.

---

## Non-goals (for now)

- No monorepo/workspace aggregation across multiple `package.json` files — scans the single project root (nearest lockfile + `package.json` to cwd).
- No interception of a manually-typed `npm install`/`yarn`/`pnpm install` run outside `:ImpostorInstall` — only that command's own install is gated.
- No backend beyond Socket CLI and the native package manager's `audit`/lockfile-only resolution.

---

## Development

```bash
make deps   # clone plenary.nvim test dep into .deps/
make test   # run the plenary busted test suite
make lint   # stylua --check and luacheck
```

---

## License

MIT
