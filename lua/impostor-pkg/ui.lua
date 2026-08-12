local M = {}

local SEVERITY_ORDER = { "critical", "high", "moderate", "low" }

local function severity_parts(findings)
  local counts = {}
  for _, finding in ipairs(findings) do
    counts[finding.severity] = (counts[finding.severity] or 0) + 1
  end

  local parts = {}
  for _, severity in ipairs(SEVERITY_ORDER) do
    if counts[severity] then
      table.insert(parts, counts[severity] .. " " .. severity)
    end
  end
  return parts
end

function M.summarize(findings)
  if #findings == 0 then
    return "impostor-pkg: no issues found"
  end

  local parts = severity_parts(findings)
  local noun = #findings == 1 and "package flagged" or "packages flagged"
  return string.format("impostor-pkg: %d %s: %s", #findings, noun, table.concat(parts, ", "))
end

function M.notify(findings)
  vim.notify(M.summarize(findings))
end

function M.notify_preinstall(result)
  if result.unchecked and #result.unchecked > 0 then
    local names = {}
    for _, dep in ipairs(result.unchecked) do
      table.insert(names, dep.name)
    end
    vim.notify(
      string.format(
        "impostor-pkg: %d new dependenc%s can't be checked without Socket (audit needs a lockfile entry): %s",
        #result.unchecked,
        #result.unchecked == 1 and "y" or "ies",
        table.concat(names, ", ")
      ),
      vim.log.levels.WARN
    )
    return
  end

  if #result.findings == 0 then
    local pending_count = result.pending and #result.pending or 0
    if pending_count > 0 then
      vim.notify(
        string.format(
          "impostor-pkg: no issues found in %d new dependenc%s",
          pending_count,
          pending_count == 1 and "y" or "ies"
        )
      )
    end
    return
  end

  local parts = severity_parts(result.findings)
  local noun = #result.findings == 1 and "new dependency flagged" or "new dependencies flagged"
  vim.notify(
    string.format("impostor-pkg: %d %s before install: %s", #result.findings, noun, table.concat(parts, ", ")),
    vim.log.levels.WARN
  )
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
