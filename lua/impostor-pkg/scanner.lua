local M = {}

local detect = require("impostor-pkg.detect")
local preinstall = require("impostor-pkg.preinstall")
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

function M.pick_backend(_package_manager)
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

  local backend = M.pick_backend(project.package_manager)

  local available
  if backend.name == "socket" then
    available = socket_backend.is_available()
  else
    available = audit_backend.is_available(project.package_manager)
  end

  if not available then
    callback({
      ok = false,
      project = project,
      error = "impostor-pkg: " .. backend.name .. " is not available (CLI not found or not authenticated)",
    })
    return
  end

  local command
  if backend.name == "socket" then
    command = backend.command_for(project.root)
  else
    command = backend.command_for(project.package_manager)
  end

  local ok, err = pcall(system_fn, command, { text = true }, function(completed)
    -- vim.system's on_exit callback runs in a libuv fast-event context; nvim_* / vim.notify /
    -- vim.diagnostic.set (all reachable via the caller-supplied callback) must not be called
    -- from there, so defer the rest of the work (and the callback) to the main loop.
    vim.schedule(function()
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
  end)

  if not ok then
    callback({
      ok = false,
      project = project,
      error = "impostor-pkg: " .. backend.name .. " failed to start: " .. tostring(err),
    })
  end
end

local function filter_to_pending(findings, pending_names)
  local filtered = {}
  for _, finding in ipairs(findings) do
    if finding.name and pending_names[finding.name] then
      table.insert(filtered, finding)
    end
  end
  return filtered
end

local function run_preinstall_socket(project, pending, pending_names, callback)
  if not socket_backend.is_available() then
    callback({
      ok = false,
      project = project,
      error = "impostor-pkg: socket is not available (CLI not found or not authenticated)",
    })
    return
  end

  local ok, err = pcall(system_fn, socket_backend.command_for(project.root), { text = true }, function(completed)
    vim.schedule(function()
      local findings = socket_backend.parse(completed.stdout or "")
      callback({
        ok = true,
        project = project,
        findings = apply_filters(filter_to_pending(findings, pending_names)),
        pending = pending,
      })
    end)
  end)

  if not ok then
    callback({ ok = false, project = project, error = "impostor-pkg: socket failed to start: " .. tostring(err) })
  end
end

local function run_preinstall_audit(project, pending, pending_names, callback)
  -- classic yarn has no lockfile-only resolve mode, so `yarn audit` cannot see deps that are
  -- only declared in package.json — surface them as explicitly unchecked instead of guessing.
  if project.package_manager == "yarn" then
    callback({ ok = true, project = project, findings = {}, pending = pending, unchecked = pending })
    return
  end

  local resolve_command = audit_backend.resolve_lockfile_only(project.package_manager)
  if not resolve_command or not audit_backend.is_available(project.package_manager) then
    callback({
      ok = false,
      project = project,
      error = "impostor-pkg: audit is not available (CLI not found) for " .. tostring(project.package_manager),
    })
    return
  end

  local resolve_ok, resolve_err = pcall(system_fn, resolve_command, { text = true }, function(resolve_completed)
    vim.schedule(function()
      if resolve_completed.code ~= 0 then
        callback({
          ok = false,
          project = project,
          error = "impostor-pkg: failed to resolve lockfile before audit (exit "
            .. tostring(resolve_completed.code)
            .. ")",
        })
        return
      end

      local audit_ok, audit_err =
        pcall(system_fn, audit_backend.command_for(project.package_manager), { text = true }, function(audit_completed)
          vim.schedule(function()
            local findings = audit_backend.parse(project.package_manager, audit_completed.stdout or "")
            callback({
              ok = true,
              project = project,
              findings = apply_filters(filter_to_pending(findings, pending_names)),
              pending = pending,
            })
          end)
        end)

      if not audit_ok then
        callback({
          ok = false,
          project = project,
          error = "impostor-pkg: audit failed to start: " .. tostring(audit_err),
        })
      end
    end)
  end)

  if not resolve_ok then
    callback({
      ok = false,
      project = project,
      error = "impostor-pkg: lockfile resolution failed to start: " .. tostring(resolve_err),
    })
  end
end

function M.run_preinstall(callback)
  local project = detect_fn()
  if not project then
    callback({ ok = true, skipped = true, project = nil, findings = {} })
    return
  end

  local pending = preinstall.pending_dependencies(project)
  if #pending == 0 then
    callback({ ok = true, skipped = true, project = project, findings = {}, pending = {} })
    return
  end

  local pending_names = {}
  for _, dep in ipairs(pending) do
    pending_names[dep.name] = true
  end

  local backend = M.pick_backend(project.package_manager)
  if backend.name == "socket" then
    run_preinstall_socket(project, pending, pending_names, callback)
  else
    run_preinstall_audit(project, pending, pending_names, callback)
  end
end

return M
