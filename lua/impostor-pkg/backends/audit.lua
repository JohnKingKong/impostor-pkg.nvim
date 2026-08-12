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

local LOCKFILE_ONLY_COMMANDS = {
  npm = { "npm", "install", "--package-lock-only" },
  pnpm = { "pnpm", "install", "--lockfile-only" },
}

function M.resolve_lockfile_only(package_manager)
  local command = LOCKFILE_ONLY_COMMANDS[package_manager]
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
