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
