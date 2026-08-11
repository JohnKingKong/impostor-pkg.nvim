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
