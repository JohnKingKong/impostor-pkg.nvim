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
