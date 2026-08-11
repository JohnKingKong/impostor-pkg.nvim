-- tests/ui_spec.lua
describe("impostor-pkg.ui", function()
  local ui

  before_each(function()
    package.loaded["impostor-pkg.ui"] = nil
    ui = require("impostor-pkg.ui")
  end)

  describe("summarize", function()
    it("reports no issues found for an empty list", function()
      assert.are.equal("impostor-pkg: no issues found", ui.summarize({}))
    end)

    it("counts findings by severity", function()
      local findings = {
        { name = "a", severity = "high" },
        { name = "b", severity = "high" },
        { name = "c", severity = "low" },
      }
      local summary = ui.summarize(findings)
      assert.is_true(summary:find("3 packages flagged") ~= nil)
      assert.is_true(summary:find("2 high") ~= nil)
      assert.is_true(summary:find("1 low") ~= nil)
    end)

    it("uses singular phrasing for exactly one finding", function()
      local summary = ui.summarize({ { name = "a", severity = "critical" } })
      assert.is_true(summary:find("1 package flagged") ~= nil)
    end)
  end)

  describe("notify", function()
    it("calls vim.notify with the summarize() output", function()
      local captured
      local original_notify = vim.notify
      vim.notify = function(msg)
        captured = msg
      end

      ui.notify({ { name = "a", severity = "high" } })

      vim.notify = original_notify
      assert.are.equal(ui.summarize({ { name = "a", severity = "high" } }), captured)
    end)
  end)

  describe("show", function()
    it("does not error and opens no window for an empty findings list", function()
      local win_count_before = #vim.api.nvim_list_wins()
      ui.show({})
      assert.are.equal(win_count_before, #vim.api.nvim_list_wins())
    end)

    it("opens exactly one floating window listing the findings", function()
      local win_count_before = #vim.api.nvim_list_wins()
      ui.show({
        { name = "left-pad", version = "1.3.0", severity = "high", backend = "audit", reason = "Prototype Pollution" },
      })
      assert.are.equal(win_count_before + 1, #vim.api.nvim_list_wins())

      local wins = vim.api.nvim_list_wins()
      local floating_win = wins[#wins]
      local bufnr = vim.api.nvim_win_get_buf(floating_win)
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local content = table.concat(lines, "\n")

      assert.is_true(content:find("left%-pad") ~= nil)
      assert.is_true(content:find("Prototype Pollution") ~= nil)

      vim.api.nvim_win_close(floating_win, true)
    end)
  end)
end)
