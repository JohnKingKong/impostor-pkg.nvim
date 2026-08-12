local M = {}

-- "info" ranks below "low" so that info-level findings from real npm/yarn audit output are
-- correctly filtered out under every valid min_severity; it is intentionally NOT a valid
-- min_severity config value (see validate_min_severity / VALID_MIN_SEVERITIES below).
local SEVERITY_RANK = { info = 0, low = 1, moderate = 2, high = 3, critical = 4 }
local VALID_MIN_SEVERITIES = { low = true, moderate = true, high = true, critical = true }

M.defaults = {
  backend = "auto",
  auto_scan_on_save = true,
  auto_scan_on_package_json_save = true,
  auto_scan_on_startup = true,
  ignore = {},
  min_severity = "low",
  confirm_threshold = "high",
}

local resolved = nil

local function validate_backend(backend)
  if backend ~= "auto" and backend ~= "socket" and backend ~= "audit" then
    error('impostor-pkg: \'backend\' must be one of "auto", "socket", "audit"')
  end
end

local function validate_min_severity(min_severity)
  if not VALID_MIN_SEVERITIES[min_severity] then
    error('impostor-pkg: \'min_severity\' must be one of "low", "moderate", "high", "critical"')
  end
end

local function validate_confirm_threshold(confirm_threshold)
  if not VALID_MIN_SEVERITIES[confirm_threshold] then
    error('impostor-pkg: \'confirm_threshold\' must be one of "low", "moderate", "high", "critical"')
  end
end

local function validate_ignore(ignore)
  for _, name in ipairs(ignore) do
    if type(name) ~= "string" or name == "" then
      error("impostor-pkg: each 'ignore' entry must be a non-empty string")
    end
  end
end

local function validate_boolean_opt(name, value)
  if type(value) ~= "boolean" then
    error("impostor-pkg: '" .. name .. "' must be a boolean")
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
  if opts.confirm_threshold then
    validate_confirm_threshold(opts.confirm_threshold)
  end
  if opts.ignore then
    validate_ignore(opts.ignore)
  end
  if opts.auto_scan_on_save ~= nil then
    validate_boolean_opt("auto_scan_on_save", opts.auto_scan_on_save)
  end
  if opts.auto_scan_on_package_json_save ~= nil then
    validate_boolean_opt("auto_scan_on_package_json_save", opts.auto_scan_on_package_json_save)
  end
  if opts.auto_scan_on_startup ~= nil then
    validate_boolean_opt("auto_scan_on_startup", opts.auto_scan_on_startup)
  end

  resolved = {
    backend = opts.backend or M.defaults.backend,
    auto_scan_on_save = opts.auto_scan_on_save,
    auto_scan_on_package_json_save = opts.auto_scan_on_package_json_save,
    auto_scan_on_startup = opts.auto_scan_on_startup,
    ignore = opts.ignore and vim.deepcopy(opts.ignore) or vim.deepcopy(M.defaults.ignore),
    min_severity = opts.min_severity or M.defaults.min_severity,
    confirm_threshold = opts.confirm_threshold or M.defaults.confirm_threshold,
  }
  if resolved.auto_scan_on_save == nil then
    resolved.auto_scan_on_save = M.defaults.auto_scan_on_save
  end
  if resolved.auto_scan_on_package_json_save == nil then
    resolved.auto_scan_on_package_json_save = M.defaults.auto_scan_on_package_json_save
  end
  if resolved.auto_scan_on_startup == nil then
    resolved.auto_scan_on_startup = M.defaults.auto_scan_on_startup
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
    error(
      "impostor-pkg: unknown severity in severity_at_least: " .. tostring(severity) .. "/" .. tostring(min_severity)
    )
  end
  return severity_value >= min_value
end

return M
