# impostor-pkg.nvim Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `impostor-pkg.nvim`, a Neovim plugin that flags malicious/risky npm, yarn, and pnpm packages by running Socket CLI (if configured) or the package manager's native `audit` command, surfacing results as a notification + floating window + inline `package.json` diagnostics.

**Architecture:** Six focused Lua modules (`detect`, `backends/audit`, `backends/socket`, `scanner`, `diagnostics`, `ui`) wired together by `init.lua`, following the exact scaffolding conventions of the sibling repo `globular-telescope.nvim` (Makefile, `.luacheckrc`, `stylua.toml`, plenary/busted tests, GitHub Actions CI, `lua/health/`).

**Tech Stack:** Lua, Neovim's built-in `vim.system` (async job control), `vim.json`, `vim.diagnostic`; plenary.nvim for tests; stylua + luacheck for lint; GitHub Actions for CI.

## Global Constraints

- Minimum Neovim version: **0.10** (required by `vim.system`, used for all async backend execution — this is a departure from `globular-telescope.nvim`'s v0.9.5 floor, which didn't need it).
- License: MIT, copyright "Jean-Rene Vigneault", same text as `globular-telescope.nvim/LICENSE` (already created at `/Users/johnkingkong/impostor-pkg.nvim/LICENSE`).
- Lint: `stylua.toml` — `column_width = 120`, `line_endings = "Unix"`, `indent_type = "Spaces"`, `indent_width = 2`, `quote_style = "AutoPreferDouble"`, `call_parentheses = "Always"`. `.luacheckrc` — `std = "luajit"`, `globals = { "vim" }`.
- Tests: plenary busted-style specs, run headless via `nvim --headless --noplugin -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"`. Every backend/CLI interaction is mocked in tests — never shell out to a real `socket`/`npm`/`yarn`/`pnpm` process in the test suite.
- No placeholder code, no TODOs shipped in any module.
- Repo root: `/Users/johnkingkong/impostor-pkg.nvim` (already `git init`'d, LICENSE and the design spec already committed... actually not yet committed — Task 1 does the first commit).

---

### Task 1: Repo scaffolding and CI

**Files:**
- Create: `/Users/johnkingkong/impostor-pkg.nvim/.gitignore`
- Create: `/Users/johnkingkong/impostor-pkg.nvim/.luacheckrc`
- Create: `/Users/johnkingkong/impostor-pkg.nvim/stylua.toml`
- Create: `/Users/johnkingkong/impostor-pkg.nvim/Makefile`
- Create: `/Users/johnkingkong/impostor-pkg.nvim/tests/minimal_init.lua`
- Create: `/Users/johnkingkong/impostor-pkg.nvim/.github/workflows/ci.yml`
- Create: `/Users/johnkingkong/impostor-pkg.nvim/README.md`

**Interfaces:**
- Produces: a working `make test` (zero specs, exits 0) and `make lint` (zero files, exits 0) that every later task's spec run depends on.

- [ ] **Step 1: Write `.gitignore`**

```
.deps/
```

- [ ] **Step 2: Write `.luacheckrc`**

```lua
std = "luajit"
globals = { "vim" }
exclude_files = { ".deps/" }
```

- [ ] **Step 3: Write `stylua.toml`**

```toml
column_width = 120
line_endings = "Unix"
indent_type = "Spaces"
indent_width = 2
quote_style = "AutoPreferDouble"
call_parentheses = "Always"
```

- [ ] **Step 4: Write `Makefile`**

```makefile
DEPS_DIR := .deps
PLENARY := $(DEPS_DIR)/plenary.nvim

.PHONY: deps test lint

deps:
	@mkdir -p $(DEPS_DIR)
	@test -d $(PLENARY) || git clone --depth 1 https://github.com/nvim-lua/plenary.nvim $(PLENARY)

test: deps
	nvim --headless --noplugin -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"

lint:
	stylua --check lua/ tests/ plugin/
	luacheck lua/ tests/ plugin/
```

- [ ] **Step 5: Write `tests/minimal_init.lua`**

```lua
vim.opt.rtp:append(".")
vim.opt.rtp:append(".deps/plenary.nvim")

vim.cmd("runtime! plugin/plenary.vim")
```

- [ ] **Step 6: Write `.github/workflows/ci.yml`**

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: JohnnyMorganz/stylua-action@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          version: latest
          args: --check lua/ tests/ plugin/
      - name: Install luacheck
        run: sudo apt-get update && sudo apt-get install -y luarocks && sudo luarocks install luacheck
      - name: Run luacheck
        run: luacheck lua/ tests/ plugin/

  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        neovim_version: ["v0.10.0", "stable"]
    steps:
      - uses: actions/checkout@v4
      - uses: rhysd/action-setup-vim@v1
        with:
          neovim: true
          version: ${{ matrix.neovim_version }}
      - name: Run tests
        run: make test
```

- [ ] **Step 7: Write `README.md`**

```markdown
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

\`\`\`lua
{
  "johnkingkong/impostor-pkg.nvim",
  event = "BufWritePost package-lock.json,yarn.lock,pnpm-lock.yaml",
  cmd = { "ImpostorCheck", "Impostor" },
  opts = {},
}
\`\`\`

## Usage

Saves to a lockfile trigger an automatic scan. Run `:ImpostorCheck` (or
`:Impostor`) to scan on demand.

## Configuration

\`\`\`lua
require("impostor-pkg").setup({
  backend = "auto",       -- "auto" | "socket" | "audit"
  auto_scan_on_save = true,
  ignore = {},             -- package names to always suppress
  min_severity = "low",    -- "low" | "moderate" | "high" | "critical"
})
\`\`\`
```

- [ ] **Step 8: Verify scaffolding**

Run: `cd /Users/johnkingkong/impostor-pkg.nvim && make deps && make test`
Expected: plenary clones successfully, test run reports `0 failed` (there are no spec files yet, so the harness runs with zero suites and exits 0). If `stylua`/`luacheck` are installed locally, also run `make lint`; expected: no errors (no `lua/`/`plugin/` files exist yet, so both commands report nothing to check — if `lua/` or `plugin/` don't exist yet, create them as empty directories with a `.gitkeep` so the lint commands don't error on a missing path, or skip local lint verification until Task 2 adds real files).

- [ ] **Step 9: Commit**

```bash
cd /Users/johnkingkong/impostor-pkg.nvim
git add .gitignore .luacheckrc stylua.toml Makefile tests/minimal_init.lua .github/workflows/ci.yml README.md LICENSE docs/
git commit -m "chore: scaffold impostor-pkg.nvim (CI, lint, test harness, design spec)"
```

---

### Task 2: `config.lua` — setup/get and severity ranking

**Files:**
- Create: `lua/impostor-pkg/config.lua`
- Test: `tests/config_spec.lua`

**Interfaces:**
- Produces: `config.setup(opts) -> resolved`, `config.get() -> resolved`, `config.severity_at_least(severity, min_severity) -> boolean`. `resolved` shape: `{ backend = "auto"|"socket"|"audit", auto_scan_on_save = boolean, ignore = string[], min_severity = "low"|"moderate"|"high"|"critical" }`. Every later task that needs config calls `require("impostor-pkg.config").get()`.

- [ ] **Step 1: Write the failing tests**

```lua
-- tests/config_spec.lua
describe("impostor-pkg.config", function()
  local config

  before_each(function()
    package.loaded["impostor-pkg.config"] = nil
    config = require("impostor-pkg.config")
  end)

  it("returns sane defaults when setup() is not called", function()
    local resolved = config.get()
    assert.are.equal("auto", resolved.backend)
    assert.is_true(resolved.auto_scan_on_save)
    assert.are.same({}, resolved.ignore)
    assert.are.equal("low", resolved.min_severity)
  end)

  it("overrides backend when a valid value is provided", function()
    config.setup({ backend = "socket" })
    assert.are.equal("socket", config.get().backend)
  end)

  it("errors when backend is not one of auto/socket/audit", function()
    assert.has_error(function()
      config.setup({ backend = "bogus" })
    end)
  end)

  it("errors when min_severity is not a known severity", function()
    assert.has_error(function()
      config.setup({ min_severity = "meh" })
    end)
  end)

  it("errors when ignore is not a list of strings", function()
    assert.has_error(function()
      config.setup({ ignore = { "left-pad", 42 } })
    end)
  end)

  it("errors when auto_scan_on_save is not a boolean", function()
    assert.has_error(function()
      config.setup({ auto_scan_on_save = "yes" })
    end)
  end)

  it("does not alias a user-supplied ignore table after setup()", function()
    local user_ignore = { "left-pad" }
    config.setup({ ignore = user_ignore })
    table.insert(user_ignore, "colors")
    assert.are.same({ "left-pad" }, config.get().ignore)
  end)

  it("does not accumulate options across repeated setup() calls", function()
    config.setup({ ignore = { "left-pad" } })
    config.setup({ backend = "audit" })
    local resolved = config.get()
    assert.are.equal("audit", resolved.backend)
    assert.are.same({}, resolved.ignore)
  end)

  describe("severity_at_least", function()
    it("returns true when severity meets or exceeds the minimum", function()
      assert.is_true(config.severity_at_least("high", "low"))
      assert.is_true(config.severity_at_least("critical", "critical"))
    end)

    it("returns false when severity is below the minimum", function()
      assert.is_false(config.severity_at_least("low", "high"))
    end)

    it("errors on an unknown severity value", function()
      assert.has_error(function()
        config.severity_at_least("bogus", "low")
      end)
    end)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/johnkingkong/impostor-pkg.nvim && make test`
Expected: FAIL — `module 'impostor-pkg.config' not found`.

- [ ] **Step 3: Write `lua/impostor-pkg/config.lua`**

```lua
local M = {}

local SEVERITY_RANK = { low = 1, moderate = 2, high = 3, critical = 4 }

M.defaults = {
  backend = "auto",
  auto_scan_on_save = true,
  ignore = {},
  min_severity = "low",
}

local resolved = nil

local function validate_backend(backend)
  if backend ~= "auto" and backend ~= "socket" and backend ~= "audit" then
    error("impostor-pkg: 'backend' must be one of \"auto\", \"socket\", \"audit\"")
  end
end

local function validate_min_severity(min_severity)
  if not SEVERITY_RANK[min_severity] then
    error("impostor-pkg: 'min_severity' must be one of \"low\", \"moderate\", \"high\", \"critical\"")
  end
end

local function validate_ignore(ignore)
  for _, name in ipairs(ignore) do
    if type(name) ~= "string" or name == "" then
      error("impostor-pkg: each 'ignore' entry must be a non-empty string")
    end
  end
end

local function validate_auto_scan_on_save(auto_scan_on_save)
  if type(auto_scan_on_save) ~= "boolean" then
    error("impostor-pkg: 'auto_scan_on_save' must be a boolean")
  end
end

function M.setup(opts)
  opts = opts or {}

  if opts.backend then
    validate_backend(opts.backend)
  end
  if opts.min_severity then
    validate_min_severity(opts.min_severity)
  end
  if opts.ignore then
    validate_ignore(opts.ignore)
  end
  if opts.auto_scan_on_save ~= nil then
    validate_auto_scan_on_save(opts.auto_scan_on_save)
  end

  resolved = {
    backend = opts.backend or M.defaults.backend,
    auto_scan_on_save = opts.auto_scan_on_save,
    ignore = opts.ignore and vim.deepcopy(opts.ignore) or vim.deepcopy(M.defaults.ignore),
    min_severity = opts.min_severity or M.defaults.min_severity,
  }
  if resolved.auto_scan_on_save == nil then
    resolved.auto_scan_on_save = M.defaults.auto_scan_on_save
  end

  return resolved
end

function M.get()
  if not resolved then
    return M.setup({})
  end
  return resolved
end

function M.severity_at_least(severity, min_severity)
  local severity_value = SEVERITY_RANK[severity]
  local min_value = SEVERITY_RANK[min_severity]
  if not severity_value or not min_value then
    error("impostor-pkg: unknown severity in severity_at_least: " .. tostring(severity) .. "/" .. tostring(min_severity))
  end
  return severity_value >= min_value
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/johnkingkong/impostor-pkg.nvim && make test`
Expected: PASS, all `config_spec.lua` assertions green.

- [ ] **Step 5: Commit**

```bash
cd /Users/johnkingkong/impostor-pkg.nvim
git add lua/impostor-pkg/config.lua tests/config_spec.lua
git commit -m "feat: add config module with setup/get and severity ranking"
```

---

### Task 3: `detect.lua` — project root, lockfile, and package manager detection

**Files:**
- Create: `lua/impostor-pkg/detect.lua`
- Test: `tests/detect_spec.lua`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `detect.LOCKFILES` (table mapping lockfile filename -> package manager name), `detect.find_project(start_dir) -> { root, package_manager, lockfile, package_json } | nil`. `scanner.lua` (Task 6) calls `detect.find_project()` with no argument (defaults to `vim.fn.getcwd()`) and consumes the returned table's `root`, `package_manager`, and `lockfile` fields.

- [ ] **Step 1: Write the failing tests**

```lua
-- tests/detect_spec.lua
local uv = vim.uv or vim.loop

local function make_tmp_dir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return dir
end

local function write_file(path, contents)
  local fd = assert(io.open(path, "w"))
  fd:write(contents or "{}")
  fd:close()
end

describe("impostor-pkg.detect", function()
  local detect

  before_each(function()
    package.loaded["impostor-pkg.detect"] = nil
    detect = require("impostor-pkg.detect")
  end)

  it("finds an npm project from a package-lock.json in the given directory", function()
    local dir = make_tmp_dir()
    write_file(dir .. "/package.json")
    write_file(dir .. "/package-lock.json")

    local project = detect.find_project(dir)

    assert.is_not_nil(project)
    assert.are.equal("npm", project.package_manager)
    assert.are.equal(dir .. "/package-lock.json", project.lockfile)
    assert.are.equal(dir .. "/package.json", project.package_json)
    assert.are.equal(dir, project.root)
  end)

  it("finds a yarn project from yarn.lock", function()
    local dir = make_tmp_dir()
    write_file(dir .. "/package.json")
    write_file(dir .. "/yarn.lock")

    local project = detect.find_project(dir)

    assert.are.equal("yarn", project.package_manager)
  end)

  it("finds a pnpm project from pnpm-lock.yaml", function()
    local dir = make_tmp_dir()
    write_file(dir .. "/package.json")
    write_file(dir .. "/pnpm-lock.yaml")

    local project = detect.find_project(dir)

    assert.are.equal("pnpm", project.package_manager)
  end)

  it("walks up parent directories to find the lockfile", function()
    local dir = make_tmp_dir()
    write_file(dir .. "/package.json")
    write_file(dir .. "/package-lock.json")
    local nested = dir .. "/src/components"
    vim.fn.mkdir(nested, "p")

    local project = detect.find_project(nested)

    assert.are.equal(dir, project.root)
  end)

  it("returns nil when no lockfile exists up to the filesystem root", function()
    local dir = make_tmp_dir()

    local project = detect.find_project(dir)

    assert.is_nil(project)
  end)

  it("prefers the nearest lockfile over a farther ancestor's lockfile", function()
    local dir = make_tmp_dir()
    write_file(dir .. "/package.json")
    write_file(dir .. "/package-lock.json")
    local nested = dir .. "/packages/app"
    vim.fn.mkdir(nested, "p")
    write_file(nested .. "/package.json")
    write_file(nested .. "/yarn.lock")

    local project = detect.find_project(nested)

    assert.are.equal(nested, project.root)
    assert.are.equal("yarn", project.package_manager)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/johnkingkong/impostor-pkg.nvim && make test`
Expected: FAIL — `module 'impostor-pkg.detect' not found`.

- [ ] **Step 3: Write `lua/impostor-pkg/detect.lua`**

```lua
local M = {}

M.LOCKFILES = {
  ["package-lock.json"] = "npm",
  ["yarn.lock"] = "yarn",
  ["pnpm-lock.yaml"] = "pnpm",
}

local uv = vim.uv or vim.loop

local function file_exists(path)
  local stat = uv.fs_stat(path)
  return stat ~= nil and stat.type == "file"
end

local function parent_of(dir)
  local trimmed = dir:gsub("/+$", "")
  local parent = trimmed:match("^(.*)/[^/]+$")
  return parent
end

function M.find_project(start_dir)
  local current = start_dir or vim.fn.getcwd()

  while current and current ~= "" do
    for lockfile_name, package_manager in pairs(M.LOCKFILES) do
      local lockfile_path = current .. "/" .. lockfile_name
      if file_exists(lockfile_path) then
        return {
          root = current,
          package_manager = package_manager,
          lockfile = lockfile_path,
          package_json = current .. "/package.json",
        }
      end
    end

    local parent = parent_of(current)
    if parent == current then
      break
    end
    current = parent
  end

  return nil
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/johnkingkong/impostor-pkg.nvim && make test`
Expected: PASS, all `detect_spec.lua` assertions green.

- [ ] **Step 5: Commit**

```bash
cd /Users/johnkingkong/impostor-pkg.nvim
git add lua/impostor-pkg/detect.lua tests/detect_spec.lua
git commit -m "feat: add detect module for project root and package manager detection"
```

---

### Task 4: `backends/audit.lua` — npm/yarn/pnpm native audit parsing

**Files:**
- Create: `lua/impostor-pkg/backends/audit.lua`
- Test: `tests/backends/audit_spec.lua`

**Interfaces:**
- Consumes: nothing from earlier tasks (operates on a `package_manager` string: `"npm"|"yarn"|"pnpm"`).
- Produces: `audit.command_for(package_manager) -> string[]`, `audit.is_available(package_manager) -> boolean`, `audit.parse(package_manager, stdout) -> Finding[]` where `Finding = { name, version, severity, backend = "audit", reason }`. `scanner.lua` (Task 6) calls all three.

- [ ] **Step 1: Write the failing tests**

```lua
-- tests/backends/audit_spec.lua
describe("impostor-pkg.backends.audit", function()
  local audit

  before_each(function()
    package.loaded["impostor-pkg.backends.audit"] = nil
    audit = require("impostor-pkg.backends.audit")
  end)

  describe("command_for", function()
    it("returns the right CLI invocation per package manager", function()
      assert.are.same({ "npm", "audit", "--json" }, audit.command_for("npm"))
      assert.are.same({ "yarn", "audit", "--json" }, audit.command_for("yarn"))
      assert.are.same({ "pnpm", "audit", "--json" }, audit.command_for("pnpm"))
    end)

    it("returns nil for an unknown package manager", function()
      assert.is_nil(audit.command_for("bun"))
    end)
  end)

  describe("parse npm", function()
    it("extracts findings from the npm 7+ vulnerabilities shape", function()
      local stdout = vim.json.encode({
        vulnerabilities = {
          ["left-pad"] = {
            name = "left-pad",
            severity = "high",
            range = "1.3.0",
            via = { { title = "Prototype Pollution", severity = "high" } },
          },
        },
      })

      local findings = audit.parse("npm", stdout)

      assert.are.equal(1, #findings)
      assert.are.equal("left-pad", findings[1].name)
      assert.are.equal("high", findings[1].severity)
      assert.are.equal("audit", findings[1].backend)
      assert.are.equal("Prototype Pollution", findings[1].reason)
    end)

    it("falls back to a generic reason when via has no title", function()
      local stdout = vim.json.encode({
        vulnerabilities = {
          ["left-pad"] = { name = "left-pad", severity = "low", via = { "some-dependency" } },
        },
      })

      local findings = audit.parse("npm", stdout)

      assert.are.equal("known vulnerability", findings[1].reason)
    end)

    it("returns an empty list for malformed JSON", function()
      assert.are.same({}, audit.parse("npm", "not json"))
    end)

    it("returns an empty list when vulnerabilities is missing", function()
      assert.are.same({}, audit.parse("npm", vim.json.encode({ metadata = {} })))
    end)
  end)

  describe("parse yarn", function()
    it("extracts findings from auditAdvisory NDJSON lines", function()
      local line1 = vim.json.encode({ type = "auditSummary", data = {} })
      local line2 = vim.json.encode({
        type = "auditAdvisory",
        data = {
          advisory = {
            module_name = "left-pad",
            severity = "moderate",
            title = "Prototype Pollution",
            vulnerable_versions = "<1.3.0",
          },
        },
      })
      local stdout = line1 .. "\n" .. line2 .. "\n"

      local findings = audit.parse("yarn", stdout)

      assert.are.equal(1, #findings)
      assert.are.equal("left-pad", findings[1].name)
      assert.are.equal("moderate", findings[1].severity)
      assert.are.equal("Prototype Pollution", findings[1].reason)
    end)

    it("skips unparseable lines without erroring", function()
      local stdout = "not json\n" .. vim.json.encode({ type = "auditSummary" })
      assert.are.same({}, audit.parse("yarn", stdout))
    end)
  end)

  describe("parse pnpm", function()
    it("extracts findings from the report.advisories shape", function()
      local stdout = vim.json.encode({
        auditReportVersion = 2,
        report = {
          advisories = {
            ["42"] = { module_name = "left-pad", severity = "critical", title = "Prototype Pollution" },
          },
        },
      })

      local findings = audit.parse("pnpm", stdout)

      assert.are.equal(1, #findings)
      assert.are.equal("left-pad", findings[1].name)
      assert.are.equal("critical", findings[1].severity)
    end)

    it("returns an empty list when report.advisories is missing", function()
      assert.are.same({}, audit.parse("pnpm", vim.json.encode({ auditReportVersion = 2 })))
    end)
  end)

  describe("is_available", function()
    it("returns false for an unknown package manager", function()
      assert.is_false(audit.is_available("bun"))
    end)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/johnkingkong/impostor-pkg.nvim && make test`
Expected: FAIL — `module 'impostor-pkg.backends.audit' not found`.

- [ ] **Step 3: Write `lua/impostor-pkg/backends/audit.lua`**

```lua
local M = {}

M.name = "audit"

local COMMANDS = {
  npm = { "npm", "audit", "--json" },
  yarn = { "yarn", "audit", "--json" },
  pnpm = { "pnpm", "audit", "--json" },
}

function M.command_for(package_manager)
  local command = COMMANDS[package_manager]
  return command and vim.deepcopy(command) or nil
end

function M.is_available(package_manager)
  local command = COMMANDS[package_manager]
  return command ~= nil and vim.fn.executable(command[1]) == 1
end

-- npm 7+ (`auditReportVersion == 2`): { vulnerabilities = { [pkg_name] = { name, severity, range, via } } }
local function parse_npm(stdout)
  local ok, decoded = pcall(vim.json.decode, stdout)
  if not ok or type(decoded) ~= "table" or type(decoded.vulnerabilities) ~= "table" then
    return {}
  end

  local findings = {}
  for name, vuln in pairs(decoded.vulnerabilities) do
    if type(vuln) == "table" and type(vuln.severity) == "string" then
      local reason = "known vulnerability"
      if type(vuln.via) == "table" then
        for _, via in ipairs(vuln.via) do
          if type(via) == "table" and type(via.title) == "string" then
            reason = via.title
            break
          end
        end
      end
      table.insert(findings, {
        name = vuln.name or name,
        version = vuln.range,
        severity = vuln.severity,
        backend = "audit",
        reason = reason,
      })
    end
  end
  return findings
end

-- yarn classic: newline-delimited JSON, one object per line; advisories are `type == "auditAdvisory"`
local function parse_yarn(stdout)
  local findings = {}
  for line in stdout:gmatch("[^\r\n]+") do
    local ok, decoded = pcall(vim.json.decode, line)
    if ok and type(decoded) == "table" and decoded.type == "auditAdvisory" then
      local advisory = type(decoded.data) == "table" and decoded.data.advisory or nil
      if type(advisory) == "table" and type(advisory.severity) == "string" then
        table.insert(findings, {
          name = advisory.module_name,
          version = advisory.vulnerable_versions,
          severity = advisory.severity,
          backend = "audit",
          reason = advisory.title or "known vulnerability",
        })
      end
    end
  end
  return findings
end

-- pnpm: { auditReportVersion, report = { advisories = { [id] = { module_name, severity, title } } } }
local function parse_pnpm(stdout)
  local ok, decoded = pcall(vim.json.decode, stdout)
  if not ok or type(decoded) ~= "table" then
    return {}
  end

  local advisories = type(decoded.report) == "table" and decoded.report.advisories or nil
  if type(advisories) ~= "table" then
    return {}
  end

  local findings = {}
  for _, advisory in pairs(advisories) do
    if type(advisory) == "table" and type(advisory.severity) == "string" then
      table.insert(findings, {
        name = advisory.module_name,
        version = advisory.vulnerable_versions,
        severity = advisory.severity,
        backend = "audit",
        reason = advisory.title or "known vulnerability",
      })
    end
  end
  return findings
end

local PARSERS = { npm = parse_npm, yarn = parse_yarn, pnpm = parse_pnpm }

function M.parse(package_manager, stdout)
  local parser = PARSERS[package_manager]
  if not parser then
    return {}
  end
  return parser(stdout or "")
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/johnkingkong/impostor-pkg.nvim && make test`
Expected: PASS, all `audit_spec.lua` assertions green.

- [ ] **Step 5: Commit**

```bash
cd /Users/johnkingkong/impostor-pkg.nvim
git add lua/impostor-pkg/backends/audit.lua tests/backends/audit_spec.lua
git commit -m "feat: add native audit backend for npm/yarn/pnpm"
```

---

### Task 5: `backends/socket.lua` — Socket CLI availability and parsing

**Files:**
- Create: `lua/impostor-pkg/backends/socket.lua`
- Test: `tests/backends/socket_spec.lua`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `socket.is_installed() -> boolean`, `socket.is_authenticated() -> boolean`, `socket.is_available() -> boolean` (installed AND authenticated), `socket.command_for(project_root) -> string[]`, `socket.parse(stdout) -> Finding[]`. `scanner.lua` (Task 6) calls all of these.

**Important caveat carried into this task:** Socket's `scan create --json` response schema is not fully nailed down by public docs at plan-writing time — the parser below targets Socket's documented components/alerts SBOM shape (`components[].alerts[]` with `type`, `severity`, and a description field). **Before shipping**, run `socket scan create <fixture-dir> --json` against a real Socket-authenticated project and diff the actual output against the fixtures in `tests/backends/socket_spec.lua`; adjust `parse_alert` field lookups if the live shape differs. This is the one module in the plan where the fixture is a best-effort reconstruction, not a verified capture.

- [ ] **Step 1: Write the failing tests**

```lua
-- tests/backends/socket_spec.lua
describe("impostor-pkg.backends.socket", function()
  local socket

  before_each(function()
    package.loaded["impostor-pkg.backends.socket"] = nil
    socket = require("impostor-pkg.backends.socket")
  end)

  describe("command_for", function()
    it("builds a scan command for the given project root", function()
      assert.are.same({ "socket", "scan", "create", "/tmp/proj", "--json" }, socket.command_for("/tmp/proj"))
    end)
  end)

  describe("parse", function()
    it("extracts findings from components with alerts", function()
      local stdout = vim.json.encode({
        components = {
          {
            type = "npm",
            name = "left-pad",
            version = "1.3.0",
            alerts = {
              { type = "knownVulnerability", severity = "high", description = "Prototype Pollution" },
            },
          },
        },
      })

      local findings = socket.parse(stdout)

      assert.are.equal(1, #findings)
      assert.are.equal("left-pad", findings[1].name)
      assert.are.equal("1.3.0", findings[1].version)
      assert.are.equal("high", findings[1].severity)
      assert.are.equal("socket", findings[1].backend)
      assert.are.equal("Prototype Pollution", findings[1].reason)
    end)

    it("produces one finding per alert when a component has multiple alerts", function()
      local stdout = vim.json.encode({
        components = {
          {
            name = "left-pad",
            version = "1.3.0",
            alerts = {
              { type = "malware", severity = "critical", description = "Known malware" },
              { type = "typosquat", severity = "high", description = "Typosquat of leftpad" },
            },
          },
        },
      })

      local findings = socket.parse(stdout)

      assert.are.equal(2, #findings)
      assert.are.equal("critical", findings[1].severity)
      assert.are.equal("high", findings[2].severity)
    end)

    it("skips components without alerts", function()
      local stdout = vim.json.encode({ components = { { name = "left-pad", version = "1.3.0" } } })
      assert.are.same({}, socket.parse(stdout))
    end)

    it("returns an empty list for malformed JSON", function()
      assert.are.same({}, socket.parse("not json"))
    end)

    it("returns an empty list when components is missing", function()
      assert.are.same({}, socket.parse(vim.json.encode({})))
    end)

    it("falls back to the alert type when description is missing", function()
      local stdout = vim.json.encode({
        components = { { name = "left-pad", alerts = { { type = "malware", severity = "critical" } } } },
      })

      local findings = socket.parse(stdout)

      assert.are.equal("malware", findings[1].reason)
    end)
  end)

  describe("is_installed", function()
    it("returns false when the socket binary is not on PATH", function()
      -- fixture-independent: the CI runner never has `socket` installed
      assert.is_false(socket.is_installed())
    end)
  end)

  describe("is_available", function()
    it("returns false when not installed regardless of authentication", function()
      assert.is_false(socket.is_available())
    end)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/johnkingkong/impostor-pkg.nvim && make test`
Expected: FAIL — `module 'impostor-pkg.backends.socket' not found`.

- [ ] **Step 3: Write `lua/impostor-pkg/backends/socket.lua`**

```lua
local M = {}

M.name = "socket"

local AUTH_ENV_VARS = {
  "SOCKET_SECURITY_API_TOKEN",
  "SOCKET_SECURITY_API_KEY",
  "SOCKET_API_TOKEN",
  "SOCKET_API_KEY",
}

function M.is_installed()
  return vim.fn.executable("socket") == 1
end

function M.is_authenticated()
  for _, var_name in ipairs(AUTH_ENV_VARS) do
    local value = vim.env[var_name]
    if value and value ~= "" then
      return true
    end
  end
  return false
end

function M.is_available()
  return M.is_installed() and M.is_authenticated()
end

function M.command_for(project_root)
  return { "socket", "scan", "create", project_root, "--json" }
end

-- Socket's SBOM-style scan output: { components = { { name, version, alerts = { { type, severity, description } } } } }
function M.parse(stdout)
  local ok, decoded = pcall(vim.json.decode, stdout)
  if not ok or type(decoded) ~= "table" or type(decoded.components) ~= "table" then
    return {}
  end

  local findings = {}
  for _, component in ipairs(decoded.components) do
    if type(component) == "table" and type(component.alerts) == "table" then
      for _, alert in ipairs(component.alerts) do
        if type(alert) == "table" and type(alert.severity) == "string" then
          table.insert(findings, {
            name = component.name,
            version = component.version,
            severity = alert.severity,
            backend = "socket",
            reason = alert.description or alert.type or "flagged by Socket",
          })
        end
      end
    end
  end
  return findings
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/johnkingkong/impostor-pkg.nvim && make test`
Expected: PASS, all `socket_spec.lua` assertions green. (`is_installed`/`is_available` pass because the CI/dev sandbox has no `socket` binary — if you're running locally with Socket CLI installed, temporarily `unset PATH`-shadow it or accept that those two specific assertions are environment-dependent and skip them locally.)

- [ ] **Step 5: Commit**

```bash
cd /Users/johnkingkong/impostor-pkg.nvim
git add lua/impostor-pkg/backends/socket.lua tests/backends/socket_spec.lua
git commit -m "feat: add Socket CLI backend (availability check + scan parsing)"
```

---

### Task 6: `scanner.lua` — backend selection, async execution, caching

**Files:**
- Create: `lua/impostor-pkg/scanner.lua`
- Test: `tests/scanner_spec.lua`

**Interfaces:**
- Consumes: `require("impostor-pkg.detect").find_project`, `require("impostor-pkg.backends.audit")`, `require("impostor-pkg.backends.socket")`, `require("impostor-pkg.config").get()` / `.severity_at_least`.
- Produces: `scanner.run(opts, callback)` where `opts = { force = boolean }` (`force = true` bypasses the lockfile-hash cache; used by the manual command) and `callback(result)` receives `{ ok = boolean, findings = Finding[]|nil, error = string|nil, project = table|nil, skipped = boolean|nil }`. `init.lua` (Task 9) and `ui`/`diagnostics` (Tasks 7-8, via `init.lua`) consume this callback's `result`.
- Injectable seams for testing: `scanner._set_system_fn(fn)` to replace `vim.system`, `scanner._set_detect_fn(fn)` to replace `detect.find_project`, both reset via `scanner._reset()`.

- [ ] **Step 1: Write the failing tests**

```lua
-- tests/scanner_spec.lua
describe("impostor-pkg.scanner", function()
  local scanner
  local config

  before_each(function()
    package.loaded["impostor-pkg.scanner"] = nil
    package.loaded["impostor-pkg.config"] = nil
    scanner = require("impostor-pkg.scanner")
    config = require("impostor-pkg.config")
    config.setup({ backend = "audit" })
  end)

  after_each(function()
    scanner._reset()
  end)

  local function stub_project()
    return { root = "/tmp/proj", package_manager = "npm", lockfile = "/tmp/proj/package-lock.json", package_json = "/tmp/proj/package.json" }
  end

  local function stub_system(stdout, exit_code)
    return function(_cmd, _opts, on_exit)
      on_exit({ code = exit_code or 0, stdout = stdout or "{}", stderr = "" })
    end
  end

  it("reports skipped=true with no project when no lockfile is found", function()
    scanner._set_detect_fn(function()
      return nil
    end)

    local result
    scanner.run({}, function(r)
      result = r
    end)

    assert.is_true(result.ok)
    assert.is_true(result.skipped)
    assert.is_nil(result.project)
  end)

  it("runs the audit backend and returns parsed findings", function()
    scanner._set_detect_fn(stub_project)
    scanner._set_system_fn(stub_system(vim.json.encode({
      vulnerabilities = { ["left-pad"] = { name = "left-pad", severity = "high", via = {} } },
    })))

    local result
    scanner.run({}, function(r)
      result = r
    end)

    assert.is_true(result.ok)
    assert.are.equal(1, #result.findings)
    assert.are.equal("left-pad", result.findings[1].name)
  end)

  it("filters out findings below min_severity", function()
    config.setup({ backend = "audit", min_severity = "high" })
    scanner._set_detect_fn(stub_project)
    scanner._set_system_fn(stub_system(vim.json.encode({
      vulnerabilities = {
        ["left-pad"] = { name = "left-pad", severity = "low", via = {} },
        ["colors"] = { name = "colors", severity = "critical", via = {} },
      },
    })))

    local result
    scanner.run({}, function(r)
      result = r
    end)

    assert.are.equal(1, #result.findings)
    assert.are.equal("colors", result.findings[1].name)
  end)

  it("filters out ignored package names", function()
    config.setup({ backend = "audit", ignore = { "left-pad" } })
    scanner._set_detect_fn(stub_project)
    scanner._set_system_fn(stub_system(vim.json.encode({
      vulnerabilities = { ["left-pad"] = { name = "left-pad", severity = "critical", via = {} } },
    })))

    local result
    scanner.run({}, function(r)
      result = r
    end)

    assert.are.same({}, result.findings)
  end)

  it("skips re-scanning when the lockfile hash is unchanged and force is not set", function()
    local call_count = 0
    scanner._set_detect_fn(stub_project)
    scanner._set_system_fn(function(_cmd, _opts, on_exit)
      call_count = call_count + 1
      on_exit({ code = 0, stdout = "{}", stderr = "" })
    end)
    scanner._set_hash_fn(function(_lockfile)
      return "same-hash"
    end)

    scanner.run({}, function() end)
    local second_result
    scanner.run({}, function(r)
      second_result = r
    end)

    assert.are.equal(1, call_count)
    assert.is_true(second_result.skipped)
  end)

  it("bypasses the cache when force=true even with an unchanged hash", function()
    local call_count = 0
    scanner._set_detect_fn(stub_project)
    scanner._set_system_fn(function(_cmd, _opts, on_exit)
      call_count = call_count + 1
      on_exit({ code = 0, stdout = "{}", stderr = "" })
    end)
    scanner._set_hash_fn(function(_lockfile)
      return "same-hash"
    end)

    scanner.run({}, function() end)
    scanner.run({ force = true }, function() end)

    assert.are.equal(2, call_count)
  end)

  it("returns ok=false with an error message when the CLI exits non-zero and stdout is unparseable", function()
    scanner._set_detect_fn(stub_project)
    scanner._set_system_fn(stub_system("not json", 1))

    local result
    scanner.run({}, function(r)
      result = r
    end)

    assert.is_false(result.ok)
    assert.is_string(result.error)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/johnkingkong/impostor-pkg.nvim && make test`
Expected: FAIL — `module 'impostor-pkg.scanner' not found`.

- [ ] **Step 3: Write `lua/impostor-pkg/scanner.lua`**

```lua
local M = {}

local detect = require("impostor-pkg.detect")
local audit_backend = require("impostor-pkg.backends.audit")
local socket_backend = require("impostor-pkg.backends.socket")
local config = require("impostor-pkg.config")

local detect_fn = detect.find_project
local system_fn = vim.system
local hash_fn = function(path)
  local fd = io.open(path, "r")
  if not fd then
    return nil
  end
  local contents = fd:read("*a")
  fd:close()
  return vim.fn.sha256(contents)
end

local last_hash_by_lockfile = {}

function M._set_detect_fn(fn)
  detect_fn = fn
end

function M._set_system_fn(fn)
  system_fn = fn
end

function M._set_hash_fn(fn)
  hash_fn = fn
end

function M._reset()
  detect_fn = detect.find_project
  system_fn = vim.system
  hash_fn = function(path)
    local fd = io.open(path, "r")
    if not fd then
      return nil
    end
    local contents = fd:read("*a")
    fd:close()
    return vim.fn.sha256(contents)
  end
  last_hash_by_lockfile = {}
end

local function pick_backend(package_manager)
  local resolved = config.get()

  if resolved.backend == "socket" then
    return socket_backend
  end
  if resolved.backend == "audit" then
    return audit_backend
  end

  if socket_backend.is_available() then
    return socket_backend
  end
  return audit_backend
end

local function apply_filters(findings)
  local resolved = config.get()
  local ignore_set = {}
  for _, name in ipairs(resolved.ignore) do
    ignore_set[name] = true
  end

  local filtered = {}
  for _, finding in ipairs(findings) do
    local ignored = finding.name and ignore_set[finding.name]
    local meets_severity = config.severity_at_least(finding.severity, resolved.min_severity)
    if not ignored and meets_severity then
      table.insert(filtered, finding)
    end
  end
  return filtered
end

function M.run(opts, callback)
  opts = opts or {}

  local project = detect_fn()
  if not project then
    callback({ ok = true, skipped = true, project = nil, findings = {} })
    return
  end

  local hash = hash_fn(project.lockfile)
  if not opts.force and hash and last_hash_by_lockfile[project.lockfile] == hash then
    callback({ ok = true, skipped = true, project = project, findings = {} })
    return
  end

  local backend = pick_backend(project.package_manager)
  local command
  if backend.name == "socket" then
    command = backend.command_for(project.root)
  else
    command = backend.command_for(project.package_manager)
  end

  system_fn(command, { text = true }, function(completed)
    local stdout = completed.stdout or ""
    -- socket backend's parse takes only stdout; audit backend's parse takes (package_manager, stdout)
    local findings
    if backend.name == "socket" then
      findings = backend.parse(stdout)
    else
      findings = backend.parse(project.package_manager, stdout)
    end

    if completed.code ~= 0 and #findings == 0 then
      callback({ ok = false, project = project, error = "impostor-pkg: " .. backend.name .. " exited with code " .. tostring(completed.code) })
      return
    end

    if hash then
      last_hash_by_lockfile[project.lockfile] = hash
    end

    callback({ ok = true, project = project, findings = apply_filters(findings) })
  end)
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/johnkingkong/impostor-pkg.nvim && make test`
Expected: PASS, all `scanner_spec.lua` assertions green.

- [ ] **Step 5: Commit**

```bash
cd /Users/johnkingkong/impostor-pkg.nvim
git add lua/impostor-pkg/scanner.lua tests/scanner_spec.lua
git commit -m "feat: add scanner orchestration (backend selection, caching, filtering)"
```

---

### Task 7: `diagnostics.lua` — mapping findings to `package.json` lines

**Files:**
- Create: `lua/impostor-pkg/diagnostics.lua`
- Test: `tests/diagnostics_spec.lua`

**Interfaces:**
- Consumes: `Finding[]` (from Task 6's `scanner.run` callback), a `package_json` path (from Task 3's `detect.find_project` result).
- Produces: `diagnostics.NAMESPACE` (the `vim.diagnostic` namespace id), `diagnostics.apply(package_json_path, findings)` (finds an already-open buffer for that path — no-op if it's not open — and sets diagnostics), `diagnostics.clear(package_json_path)`. `init.lua` (Task 9) calls both.

- [ ] **Step 1: Write the failing tests**

```lua
-- tests/diagnostics_spec.lua
describe("impostor-pkg.diagnostics", function()
  local diagnostics
  local bufnr
  local path

  before_each(function()
    package.loaded["impostor-pkg.diagnostics"] = nil
    diagnostics = require("impostor-pkg.diagnostics")

    path = vim.fn.tempname() .. "-package.json"
    local fd = assert(io.open(path, "w"))
    fd:write('{\n  "name": "demo",\n  "dependencies": {\n    "left-pad": "1.3.0",\n    "colors": "1.4.0"\n  }\n}\n')
    fd:close()

    bufnr = vim.fn.bufadd(path)
    vim.fn.bufload(bufnr)
  end)

  after_each(function()
    diagnostics.clear(path)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    os.remove(path)
  end)

  it("sets a diagnostic on the line declaring the flagged package", function()
    diagnostics.apply(path, {
      { name = "left-pad", severity = "high", backend = "audit", reason = "Prototype Pollution" },
    })

    local diags = vim.diagnostic.get(bufnr, { namespace = diagnostics.NAMESPACE })

    assert.are.equal(1, #diags)
    assert.are.equal(2, diags[1].lnum) -- 0-indexed: line 3 ("left-pad": ...) is index 2
    assert.is_true(diags[1].message:find("Prototype Pollution") ~= nil)
  end)

  it("sets one diagnostic per finding when multiple packages are flagged", function()
    diagnostics.apply(path, {
      { name = "left-pad", severity = "high", backend = "audit", reason = "r1" },
      { name = "colors", severity = "critical", backend = "audit", reason = "r2" },
    })

    local diags = vim.diagnostic.get(bufnr, { namespace = diagnostics.NAMESPACE })
    assert.are.equal(2, #diags)
  end)

  it("maps severity to vim.diagnostic.severity levels", function()
    diagnostics.apply(path, { { name = "left-pad", severity = "critical", backend = "audit", reason = "r" } })
    local diags = vim.diagnostic.get(bufnr, { namespace = diagnostics.NAMESPACE })
    assert.are.equal(vim.diagnostic.severity.ERROR, diags[1].severity)
  end)

  it("skips a finding whose package name is not found in the buffer", function()
    diagnostics.apply(path, { { name = "does-not-exist", severity = "high", backend = "audit", reason = "r" } })
    local diags = vim.diagnostic.get(bufnr, { namespace = diagnostics.NAMESPACE })
    assert.are.equal(0, #diags)
  end)

  it("is a no-op when the package.json path has no open buffer", function()
    -- should not error even though nothing is loaded for this path
    diagnostics.apply("/tmp/does-not-exist/package.json", { { name = "x", severity = "low", backend = "audit", reason = "r" } })
  end)

  it("clear() removes all diagnostics set by apply()", function()
    diagnostics.apply(path, { { name = "left-pad", severity = "high", backend = "audit", reason = "r" } })
    diagnostics.clear(path)
    local diags = vim.diagnostic.get(bufnr, { namespace = diagnostics.NAMESPACE })
    assert.are.equal(0, #diags)
  end)

  it("replaces previous diagnostics rather than accumulating on repeated apply() calls", function()
    diagnostics.apply(path, { { name = "left-pad", severity = "high", backend = "audit", reason = "r1" } })
    diagnostics.apply(path, { { name = "colors", severity = "low", backend = "audit", reason = "r2" } })
    local diags = vim.diagnostic.get(bufnr, { namespace = diagnostics.NAMESPACE })
    assert.are.equal(1, #diags)
    assert.is_true(diags[1].message:find("r2") ~= nil)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/johnkingkong/impostor-pkg.nvim && make test`
Expected: FAIL — `module 'impostor-pkg.diagnostics' not found`.

- [ ] **Step 3: Write `lua/impostor-pkg/diagnostics.lua`**

```lua
local M = {}

M.NAMESPACE = vim.api.nvim_create_namespace("impostor-pkg")

local SEVERITY_MAP = {
  low = vim.diagnostic.severity.HINT,
  moderate = vim.diagnostic.severity.WARN,
  high = vim.diagnostic.severity.ERROR,
  critical = vim.diagnostic.severity.ERROR,
}

local function bufnr_for_path(path)
  local bufnr = vim.fn.bufnr(path)
  if bufnr == -1 or not vim.api.nvim_buf_is_loaded(bufnr) then
    return nil
  end
  return bufnr
end

local function line_for_package(bufnr, name)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local pattern = '"' .. name:gsub("([^%w])", "%%%1") .. '"%s*:'
  for i, line in ipairs(lines) do
    if line:find(pattern) then
      return i - 1 -- 0-indexed
    end
  end
  return nil
end

function M.apply(package_json_path, findings)
  local bufnr = bufnr_for_path(package_json_path)
  if not bufnr then
    return
  end

  local diags = {}
  for _, finding in ipairs(findings) do
    local lnum = finding.name and line_for_package(bufnr, finding.name)
    if lnum then
      table.insert(diags, {
        lnum = lnum,
        col = 0,
        severity = SEVERITY_MAP[finding.severity] or vim.diagnostic.severity.WARN,
        source = "impostor-pkg",
        message = string.format("[%s] %s (%s)", finding.severity, finding.reason, finding.backend),
      })
    end
  end

  vim.diagnostic.set(M.NAMESPACE, bufnr, diags)
end

function M.clear(package_json_path)
  local bufnr = bufnr_for_path(package_json_path)
  if not bufnr then
    return
  end
  vim.diagnostic.set(M.NAMESPACE, bufnr, {})
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/johnkingkong/impostor-pkg.nvim && make test`
Expected: PASS, all `diagnostics_spec.lua` assertions green.

- [ ] **Step 5: Commit**

```bash
cd /Users/johnkingkong/impostor-pkg.nvim
git add lua/impostor-pkg/diagnostics.lua tests/diagnostics_spec.lua
git commit -m "feat: add diagnostics module mapping findings to package.json lines"
```

---

### Task 8: `ui.lua` — notification summary and floating window

**Files:**
- Create: `lua/impostor-pkg/ui.lua`
- Test: `tests/ui_spec.lua`

**Interfaces:**
- Consumes: `Finding[]` (from Task 6).
- Produces: `ui.summarize(findings) -> string` (pure, used both for the notify line and unit-testable independent of any window), `ui.notify(findings)` (calls `vim.notify` with `ui.summarize`'s output), `ui.show(findings)` (opens the floating window; no-op with an info notify if `findings` is empty). `init.lua` (Task 9) calls `ui.notify` and `ui.show` together after every scan.

- [ ] **Step 1: Write the failing tests**

```lua
-- tests/ui_spec.lua
describe("impostor-pkg.ui", function()
  local ui

  before_each(function()
    package.loaded["impostor-pkg.ui"] = nil
    ui = require("impostor-pkg.ui")
  end)

  describe("summarize", function()
    it("reports no issues found for an empty list", function()
      assert.are.equal("impostor-pkg: no issues found", ui.summarize({}))
    end)

    it("counts findings by severity", function()
      local findings = {
        { name = "a", severity = "high" },
        { name = "b", severity = "high" },
        { name = "c", severity = "low" },
      }
      local summary = ui.summarize(findings)
      assert.is_true(summary:find("3 packages flagged") ~= nil)
      assert.is_true(summary:find("2 high") ~= nil)
      assert.is_true(summary:find("1 low") ~= nil)
    end)

    it("uses singular phrasing for exactly one finding", function()
      local summary = ui.summarize({ { name = "a", severity = "critical" } })
      assert.is_true(summary:find("1 package flagged") ~= nil)
    end)
  end)

  describe("notify", function()
    it("calls vim.notify with the summarize() output", function()
      local captured
      local original_notify = vim.notify
      vim.notify = function(msg)
        captured = msg
      end

      ui.notify({ { name = "a", severity = "high" } })

      vim.notify = original_notify
      assert.are.equal(ui.summarize({ { name = "a", severity = "high" } }), captured)
    end)
  end)

  describe("show", function()
    it("does not error and opens no window for an empty findings list", function()
      local win_count_before = #vim.api.nvim_list_wins()
      ui.show({})
      assert.are.equal(win_count_before, #vim.api.nvim_list_wins())
    end)

    it("opens exactly one floating window listing the findings", function()
      local win_count_before = #vim.api.nvim_list_wins()
      ui.show({ { name = "left-pad", version = "1.3.0", severity = "high", backend = "audit", reason = "Prototype Pollution" } })
      assert.are.equal(win_count_before + 1, #vim.api.nvim_list_wins())

      local wins = vim.api.nvim_list_wins()
      local floating_win = wins[#wins]
      local bufnr = vim.api.nvim_win_get_buf(floating_win)
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local content = table.concat(lines, "\n")

      assert.is_true(content:find("left%-pad") ~= nil)
      assert.is_true(content:find("Prototype Pollution") ~= nil)

      vim.api.nvim_win_close(floating_win, true)
    end)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/johnkingkong/impostor-pkg.nvim && make test`
Expected: FAIL — `module 'impostor-pkg.ui' not found`.

- [ ] **Step 3: Write `lua/impostor-pkg/ui.lua`**

```lua
local M = {}

function M.summarize(findings)
  if #findings == 0 then
    return "impostor-pkg: no issues found"
  end

  local counts = {}
  local order = { "critical", "high", "moderate", "low" }
  for _, finding in ipairs(findings) do
    counts[finding.severity] = (counts[finding.severity] or 0) + 1
  end

  local parts = {}
  for _, severity in ipairs(order) do
    if counts[severity] then
      table.insert(parts, counts[severity] .. " " .. severity)
    end
  end

  local noun = #findings == 1 and "package flagged" or "packages flagged"
  return string.format("impostor-pkg: %d %s: %s", #findings, noun, table.concat(parts, ", "))
end

function M.notify(findings)
  vim.notify(M.summarize(findings))
end

local function render_lines(findings)
  local lines = {}
  for _, finding in ipairs(findings) do
    table.insert(
      lines,
      string.format(
        "[%s] %s@%s (%s) - %s",
        finding.severity,
        finding.name or "?",
        finding.version or "?",
        finding.backend or "?",
        finding.reason or ""
      )
    )
  end
  return lines
end

function M.show(findings)
  if #findings == 0 then
    return
  end

  local lines = render_lines(findings)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].bufhidden = "wipe"

  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, #line)
  end
  width = math.min(width + 2, math.floor(vim.o.columns * 0.8))
  local height = math.min(#lines, math.floor(vim.o.lines * 0.6))

  local win = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " impostor-pkg ",
  })

  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = bufnr, silent = true })
  vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = bufnr, silent = true })

  return win
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/johnkingkong/impostor-pkg.nvim && make test`
Expected: PASS, all `ui_spec.lua` assertions green.

- [ ] **Step 5: Commit**

```bash
cd /Users/johnkingkong/impostor-pkg.nvim
git add lua/impostor-pkg/ui.lua tests/ui_spec.lua
git commit -m "feat: add ui module (notify summary + floating results window)"
```

---

### Task 9: `init.lua`, `plugin/impostor-pkg.lua`, `lua/health/impostor-pkg.lua` — wiring it all together

**Files:**
- Create: `lua/impostor-pkg/init.lua`
- Create: `plugin/impostor-pkg.lua`
- Create: `lua/health/impostor-pkg.lua`
- Test: `tests/init_spec.lua`

**Interfaces:**
- Consumes: `config.setup`/`.get` (Task 2), `scanner.run` (Task 6), `ui.notify`/`.show` (Task 8), `diagnostics.apply` (Task 7), `detect.LOCKFILES` (Task 3), `socket_backend.is_installed`/`.is_authenticated` (Task 5).
- Produces: `M.setup(opts)`, `M.check(check_opts)` where `check_opts = { force = boolean }` (defaults `force = false`). `plugin/impostor-pkg.lua` calls `require("impostor-pkg").check({ force = true })` from both `:ImpostorCheck` and `:Impostor`.

- [ ] **Step 1: Write the failing tests**

```lua
-- tests/init_spec.lua
describe("impostor-pkg.init", function()
  local impostor_pkg
  local scanner

  before_each(function()
    for _, mod in ipairs({ "impostor-pkg", "impostor-pkg.init", "impostor-pkg.config", "impostor-pkg.scanner" }) do
      package.loaded[mod] = nil
    end
    impostor_pkg = require("impostor-pkg")
    scanner = require("impostor-pkg.scanner")
  end)

  after_each(function()
    scanner._reset()
  end)

  it("setup() does not error with no options", function()
    assert.has_no.errors(function()
      impostor_pkg.setup()
    end)
  end)

  it("setup() does not error with valid options", function()
    assert.has_no.errors(function()
      impostor_pkg.setup({ backend = "audit", min_severity = "high" })
    end)
  end)

  it("check() calls scanner.run and does not error when no project is found", function()
    scanner._set_detect_fn(function()
      return nil
    end)

    assert.has_no.errors(function()
      impostor_pkg.check()
    end)
  end)

  it("check() surfaces findings via ui.notify without erroring", function()
    scanner._set_detect_fn(function()
      return { root = "/tmp/proj", package_manager = "npm", lockfile = "/tmp/proj/package-lock.json", package_json = "/tmp/proj/package.json" }
    end)
    scanner._set_system_fn(function(_cmd, _opts, on_exit)
      on_exit({
        code = 0,
        stdout = vim.json.encode({
          vulnerabilities = { ["left-pad"] = { name = "left-pad", severity = "high", via = {} } },
        }),
        stderr = "",
      })
    end)

    assert.has_no.errors(function()
      impostor_pkg.check()
    end)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/johnkingkong/impostor-pkg.nvim && make test`
Expected: FAIL — `module 'impostor-pkg' not found`.

- [ ] **Step 3: Write `lua/impostor-pkg/init.lua`**

```lua
local M = {}

local config = require("impostor-pkg.config")
local scanner = require("impostor-pkg.scanner")
local ui = require("impostor-pkg.ui")
local diagnostics = require("impostor-pkg.diagnostics")
local detect = require("impostor-pkg.detect")
local socket_backend = require("impostor-pkg.backends.socket")

local AUGROUP = vim.api.nvim_create_augroup("impostor-pkg", { clear = true })
local notified_socket_status = false

local function notify_socket_status_once()
  if notified_socket_status then
    return
  end
  notified_socket_status = true

  if not socket_backend.is_available() then
    vim.notify(
      "impostor-pkg: Socket CLI not configured — using npm/yarn/pnpm audit only. "
        .. "Run `socket login` anytime to enable full malicious-package detection.",
      vim.log.levels.INFO
    )
  end
end

function M.check(check_opts)
  check_opts = check_opts or {}

  scanner.run({ force = check_opts.force }, function(result)
    if result.skipped then
      return
    end

    if not result.ok then
      vim.notify(result.error, vim.log.levels.WARN)
      return
    end

    ui.notify(result.findings)
    ui.show(result.findings)

    if result.project then
      diagnostics.apply(result.project.package_json, result.findings)
    end
  end)
end

function M.setup(opts)
  config.setup(opts)
  notify_socket_status_once()

  local resolved = config.get()
  if resolved.auto_scan_on_save then
    local lockfile_patterns = {}
    for lockfile_name, _ in pairs(detect.LOCKFILES) do
      table.insert(lockfile_patterns, "*/" .. lockfile_name)
    end

    vim.api.nvim_create_autocmd("BufWritePost", {
      group = AUGROUP,
      pattern = lockfile_patterns,
      callback = function()
        M.check({ force = false })
      end,
      desc = "impostor-pkg: scan on lockfile save",
    })
  end
end

return M
```

- [ ] **Step 4: Write `plugin/impostor-pkg.lua`**

```lua
if vim.g.loaded_impostor_pkg then
  return
end
vim.g.loaded_impostor_pkg = true

vim.api.nvim_create_user_command("ImpostorCheck", function()
  require("impostor-pkg").check({ force = true })
end, {
  desc = "Scan the current project's npm/yarn/pnpm dependencies for malicious or risky packages",
})

vim.api.nvim_create_user_command("Impostor", function()
  require("impostor-pkg").check({ force = true })
end, {
  desc = "Alias for :ImpostorCheck",
})
```

- [ ] **Step 5: Write `lua/health/impostor-pkg.lua`**

```lua
local M = {}

function M.check()
  local health = vim.health
  local start = health.start or health.report_start
  local report_ok = health.ok or health.report_ok
  local report_warn = health.warn or health.report_warn
  local report_error = health.error or health.report_error

  start("impostor-pkg")

  local socket_backend = require("impostor-pkg.backends.socket")
  if socket_backend.is_installed() then
    report_ok("socket CLI found on $PATH")
    if socket_backend.is_authenticated() then
      report_ok("socket CLI appears authenticated")
    else
      report_warn("socket CLI installed but no API token found — run `socket login`, falling back to native audit")
    end
  else
    report_warn("socket CLI not found on $PATH — falling back to npm/yarn/pnpm audit only")
  end

  local detect = require("impostor-pkg.detect")
  local audit_backend = require("impostor-pkg.backends.audit")
  local any_pm_available = false
  for _, package_manager in pairs(detect.LOCKFILES) do
    if audit_backend.is_available(package_manager) then
      any_pm_available = true
    end
  end
  if any_pm_available then
    report_ok("at least one of npm/yarn/pnpm found on $PATH")
  else
    report_error("none of npm/yarn/pnpm found on $PATH — impostor-pkg cannot run any backend")
  end
end

return M
```

- [ ] **Step 6: Run test to verify it passes**

Run: `cd /Users/johnkingkong/impostor-pkg.nvim && make test`
Expected: PASS, all `init_spec.lua` assertions green (and every earlier spec file still green).

- [ ] **Step 7: Commit**

```bash
cd /Users/johnkingkong/impostor-pkg.nvim
git add lua/impostor-pkg/init.lua plugin/impostor-pkg.lua lua/health/impostor-pkg.lua tests/init_spec.lua
git commit -m "feat: wire up setup(), commands, autocmd, and :checkhealth"
```

---

### Task 10: Vim help docs and final polish

**Files:**
- Create: `doc/impostor-pkg.txt`

**Interfaces:**
- Consumes: nothing (documentation only).
- Produces: `:help impostor-pkg` inside Neovim once the plugin's `doc/` is on `rtp` and `helptags` has run.

- [ ] **Step 1: Write `doc/impostor-pkg.txt`**

```text
*impostor-pkg.txt*    Flag malicious/risky npm, yarn, and pnpm packages

==============================================================================
CONTENTS                                                *impostor-pkg-contents*

    1. Introduction .......... |impostor-pkg-introduction|
    2. Setup ................. |impostor-pkg-setup|
    3. Commands .............. |impostor-pkg-commands|
    4. Configuration ......... |impostor-pkg-configuration|

==============================================================================
1. Introduction                                     *impostor-pkg-introduction*

impostor-pkg.nvim flags malicious, typosquatted, or otherwise risky
npm/yarn/pnpm packages — the Neovim equivalent of WebStorm's package risk
warnings. It uses Socket CLI when installed and authenticated
(`socket login`), and falls back to the project's native `npm audit` /
`yarn audit` / `pnpm audit` otherwise.

==============================================================================
2. Setup                                                   *impostor-pkg-setup*

>lua
    require("impostor-pkg").setup({})
<

==============================================================================
3. Commands                                              *impostor-pkg-commands*

:ImpostorCheck                                                *:ImpostorCheck*
:Impostor                                                          *:Impostor*
    Scan the current project's dependencies for malicious or risky
    packages. Also runs automatically on saving a lockfile
    (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`) unless
    |impostor-pkg-configuration| disables it.

==============================================================================
4. Configuration                                    *impostor-pkg-configuration*

>lua
    require("impostor-pkg").setup({
      backend = "auto",       -- "auto" | "socket" | "audit"
      auto_scan_on_save = true,
      ignore = {},             -- package names to always suppress
      min_severity = "low",    -- "low" | "moderate" | "high" | "critical"
    })
<

 vim:tw=78:ts=8:ft=help:norl:
```

- [ ] **Step 2: Verify help tags generate cleanly**

Run: `cd /Users/johnkingkong/impostor-pkg.nvim && nvim --headless -c "helptags doc" -c "q"`
Expected: exits 0, creates `doc/tags` with no errors printed.

- [ ] **Step 3: Run the full suite and lint one more time**

Run: `cd /Users/johnkingkong/impostor-pkg.nvim && make test && make lint`
Expected: all specs across every module pass; `stylua --check` and `luacheck` both report no issues.

- [ ] **Step 4: Commit**

```bash
cd /Users/johnkingkong/impostor-pkg.nvim
git add doc/impostor-pkg.txt doc/tags
git commit -m "docs: add vimdoc help file"
```

---

## Follow-up (not part of this plan)

- Add `lua/plugins/impostor-pkg.lua` to the `johnkingkong/nvim-config` repo once this plugin is pushed to GitHub, following the `claude-reviewer.lua`/`globular-telescope.lua` pattern.
- Verify the Socket `scan create --json` schema against a live authenticated run (see the caveat in Task 5) and adjust `backends/socket.lua`'s `parse` if the real field names differ.
- Push `impostor-pkg.nvim` to `github.com/johnkingkong/impostor-pkg.nvim`.
- Second plugin from the original request — a lazy.nvim plugin-source risk scanner — is a separate brainstorm/spec/plan cycle.
