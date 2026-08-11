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
