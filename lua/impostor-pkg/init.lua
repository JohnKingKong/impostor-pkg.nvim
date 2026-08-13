local M = {}

local config = require("impostor-pkg.config")
local scanner = require("impostor-pkg.scanner")
local ui = require("impostor-pkg.ui")
local diagnostics = require("impostor-pkg.diagnostics")
local detect = require("impostor-pkg.detect")
local socket_backend = require("impostor-pkg.backends.socket")

local AUGROUP = vim.api.nvim_create_augroup("impostor-pkg", { clear = true })
local notified_socket_status = false

local INSTALL_COMMANDS = {
  npm = { "npm", "install" },
  yarn = { "yarn", "install" },
  pnpm = { "pnpm", "install" },
}

local jobstart_fn = vim.fn.jobstart
local confirm_fn = vim.fn.confirm

function M._set_jobstart_fn(fn)
  jobstart_fn = fn
end

function M._set_confirm_fn(fn)
  confirm_fn = fn
end

function M._reset_install_fns()
  jobstart_fn = vim.fn.jobstart
  confirm_fn = vim.fn.confirm
end

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

-- Diagnostics can only attach to an already-loaded buffer (diagnostics.apply no-ops otherwise —
-- see bufnr_for_path). A scan can finish before the user has ever opened package.json (e.g.
-- `nvim .` opens a file explorer, not the file itself), so the last findings applied for each
-- project are cached here and replayed by the BufReadPost autocmd below the moment that buffer
-- actually loads, without needing a fresh scan.
local last_findings_by_project = {}

-- detect.lua's path and the buffer's registered name can resolve differently when a directory
-- in the path is a symlink (e.g. macOS's /tmp -> /private/tmp, or /var/folders/...) — Neovim
-- normalizes a loaded buffer's name to the real, resolved path, so cache keys are normalized the
-- same way on both the write and read side to avoid a spurious mismatch.
local function realpath(path)
  return (vim.uv.fs_realpath(path)) or path
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
      last_findings_by_project[realpath(result.project.package_json)] = result.findings
    end
  end)
end

-- The passive package.json autocmd and :ImpostorInstall each independently trigger a
-- scanner.run_preinstall call, which (for audit-only npm/pnpm) spawns real subprocesses that
-- mutate the lockfile on disk. Running two such scans concurrently races on that same file, so
-- every call is funneled through this single-flight queue: only one scanner.run_preinstall runs
-- at a time, and any call arriving while one is in flight waits its turn instead of racing it.
local preinstall_scan_queue = {}
local preinstall_scan_running = false

local function process_preinstall_scan_queue()
  if preinstall_scan_running or #preinstall_scan_queue == 0 then
    return
  end
  preinstall_scan_running = true
  local next_callback = table.remove(preinstall_scan_queue, 1)
  scanner.run_preinstall(function(result)
    preinstall_scan_running = false
    next_callback(result)
    process_preinstall_scan_queue()
  end)
end

local function run_preinstall_exclusive(callback)
  table.insert(preinstall_scan_queue, callback)
  process_preinstall_scan_queue()
end

function M.check_preinstall(on_done)
  on_done = on_done or function() end

  run_preinstall_exclusive(function(result)
    if result.skipped then
      on_done()
      return
    end

    if not result.ok then
      vim.notify(result.error, vim.log.levels.WARN)
      on_done()
      return
    end

    ui.notify_preinstall(result)

    if result.project then
      diagnostics.apply(result.project.package_json, result.findings)
      last_findings_by_project[realpath(result.project.package_json)] = result.findings
    end

    on_done()
  end)
end

local preinstall_debounce_id = 0
local preinstall_scan_in_flight = false

local function debounced_check_preinstall()
  preinstall_debounce_id = preinstall_debounce_id + 1
  local id = preinstall_debounce_id
  vim.defer_fn(function()
    if id ~= preinstall_debounce_id or preinstall_scan_in_flight then
      return
    end
    preinstall_scan_in_flight = true
    M.check_preinstall(function()
      preinstall_scan_in_flight = false
    end)
  end, 500)
end

M._debounced_check_preinstall = debounced_check_preinstall

local function run_install_terminal(project)
  local command = INSTALL_COMMANDS[project.package_manager]
  vim.cmd("split")
  jobstart_fn(command, { term = true, cwd = project.root })
  vim.cmd("startinsert")
end

function M.install()
  run_preinstall_exclusive(function(result)
    if result.skipped and not result.project then
      vim.notify("impostor-pkg: no npm/yarn/pnpm project detected", vim.log.levels.WARN)
      return
    end

    if result.skipped then
      run_install_terminal(result.project)
      return
    end

    if not result.ok then
      vim.notify(result.error, vim.log.levels.WARN)
      return
    end

    ui.notify_preinstall(result)
    if result.project then
      diagnostics.apply(result.project.package_json, result.findings)
      last_findings_by_project[realpath(result.project.package_json)] = result.findings
    end

    local resolved = config.get()
    local blocking_severity = false
    for _, finding in ipairs(result.findings) do
      if config.severity_at_least(finding.severity, resolved.confirm_threshold) then
        blocking_severity = true
        break
      end
    end
    local blocking_unchecked = result.unchecked ~= nil and #result.unchecked > 0

    if blocking_severity or blocking_unchecked then
      local message
      if blocking_severity and blocking_unchecked then
        message = string.format(
          "impostor-pkg: a flagged dependency meets or exceeds '%s' severity, and %d dependenc%s "
            .. "could not be verified without Socket. Install anyway?",
          resolved.confirm_threshold,
          #result.unchecked,
          #result.unchecked == 1 and "y" or "ies"
        )
      elseif blocking_unchecked then
        message = string.format(
          "impostor-pkg: %d new dependenc%s could not be verified without Socket. Install anyway?",
          #result.unchecked,
          #result.unchecked == 1 and "y" or "ies"
        )
      else
        message = "impostor-pkg: a flagged dependency meets or exceeds '"
          .. resolved.confirm_threshold
          .. "' severity. Install anyway?"
      end

      local choice = confirm_fn(message, "&Yes\n&No", 2)
      if choice ~= 1 then
        vim.notify("impostor-pkg: install cancelled", vim.log.levels.WARN)
        return
      end
    end

    run_install_terminal(result.project)
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

  if resolved.auto_scan_on_package_json_save then
    vim.api.nvim_create_autocmd("BufWritePost", {
      group = AUGROUP,
      pattern = "*/package.json",
      callback = function()
        debounced_check_preinstall()
      end,
      desc = "impostor-pkg: pre-install scan on package.json save",
    })
  end

  if resolved.auto_scan_on_startup then
    vim.api.nvim_create_autocmd("VimEnter", {
      group = AUGROUP,
      callback = function()
        M.check({ force = false })
        M.check_preinstall()
      end,
      desc = "impostor-pkg: scan on startup",
    })
  end

  vim.api.nvim_create_autocmd("BufReadPost", {
    group = AUGROUP,
    pattern = "*/package.json",
    callback = function(args)
      local path = vim.api.nvim_buf_get_name(args.buf)
      local cached = last_findings_by_project[realpath(path)]
      if cached then
        diagnostics.apply(path, cached)
      end
    end,
    desc = "impostor-pkg: reapply cached diagnostics once package.json's buffer loads",
  })
end

return M
