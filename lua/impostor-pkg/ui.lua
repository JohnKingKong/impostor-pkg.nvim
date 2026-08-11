local M = {}

function M.summarize(findings)
  if #findings == 0 then
    return "impostor-pkg: no issues found"
  end

  local counts = {}
  local order = { "critical", "high", "moderate", "low" }
  for _, finding in ipairs(findings) do
    counts[finding.severity] = (counts[finding.severity] or 0) + 1
  end

  local parts = {}
  for _, severity in ipairs(order) do
    if counts[severity] then
      table.insert(parts, counts[severity] .. " " .. severity)
    end
  end

  local noun = #findings == 1 and "package flagged" or "packages flagged"
  return string.format("impostor-pkg: %d %s: %s", #findings, noun, table.concat(parts, ", "))
end

function M.notify(findings)
  vim.notify(M.summarize(findings))
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
