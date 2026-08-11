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

local function pick_backend(_package_manager)
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
      callback({
        ok = false,
        project = project,
        error = "impostor-pkg: " .. backend.name .. " exited with code " .. tostring(completed.code),
      })
      return
    end

    if hash then
      last_hash_by_lockfile[project.lockfile] = hash
    end

    callback({ ok = true, project = project, findings = apply_filters(findings) })
  end)
end

return M
