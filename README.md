# impostor-pkg.nvim

Flags malicious, typosquatted, or otherwise risky npm/yarn/pnpm packages —
the Neovim equivalent of WebStorm's package risk warnings.

Uses [Socket CLI](https://docs.socket.dev/docs/socket-cli) when it's
installed and authenticated (`socket login`) for real malicious-package
detection, and falls back to the project's native `npm audit` / `yarn audit`
/ `pnpm audit` otherwise.

## Requirements

- Neovim >= 0.10
- Optional: [Socket CLI](https://docs.socket.dev/docs/socket-cli) (`npm i -g @socketsecurity/cli`, then `socket login`) for full malicious-package detection

## Installation (lazy.nvim)

```lua
{
  "johnkingkong/impostor-pkg.nvim",
  event = "BufWritePost package-lock.json,yarn.lock,pnpm-lock.yaml",
  cmd = { "ImpostorCheck", "Impostor" },
  opts = {},
}
```

## Usage

Saves to a lockfile trigger an automatic scan. Run `:ImpostorCheck` (or
`:Impostor`) to scan on demand.

## Configuration

```lua
require("impostor-pkg").setup({
  backend = "auto",       -- "auto" | "socket" | "audit"
  auto_scan_on_save = true,
  ignore = {},             -- package names to always suppress
  min_severity = "low",    -- "low" | "moderate" | "high" | "critical"
})
```
