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

  describe("notify_preinstall", function()
    it("warns with the unchecked dependency names when present", function()
      local captured
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        captured = { msg = msg, level = level }
      end

      ui.notify_preinstall({
        ok = true,
        findings = {},
        pending = { { name = "new-dep", version = "^1.0.0" } },
        unchecked = { { name = "new-dep", version = "^1.0.0" } },
      })

      vim.notify = original_notify
      assert.is_not_nil(captured)
      assert.matches("new%-dep", captured.msg)
      assert.are.equal(vim.log.levels.WARN, captured.level)
    end)

    it("warns with a severity breakdown when findings are present", function()
      local captured
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        captured = { msg = msg, level = level }
      end

      ui.notify_preinstall({
        ok = true,
        findings = { { name = "new-dep", severity = "high", backend = "audit", reason = "known vulnerability" } },
        pending = { { name = "new-dep", version = "^1.0.0" } },
      })

      vim.notify = original_notify
      assert.is_not_nil(captured)
      assert.matches("1 high", captured.msg)
      assert.are.equal(vim.log.levels.WARN, captured.level)
    end)

    it("notifies cleanly when pending deps were checked and nothing was flagged", function()
      local captured
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        captured = { msg = msg, level = level }
      end

      ui.notify_preinstall({
        ok = true,
        findings = {},
        pending = { { name = "new-dep", version = "^1.0.0" } },
      })

      vim.notify = original_notify
      assert.is_not_nil(captured)
      assert.matches("no issues found", captured.msg)
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

    it("does not register an 'i' keymap when on_ignore is not provided", function()
      ui.show({
        { name = "left-pad", version = "1.3.0", severity = "high", backend = "audit", reason = "..." },
      })
      local wins = vim.api.nvim_list_wins()
      local floating_win = wins[#wins]
      local bufnr = vim.api.nvim_win_get_buf(floating_win)

      local buf_keymaps = vim.api.nvim_buf_get_keymap(bufnr, "n")
      local has_i = false
      for _, km in ipairs(buf_keymaps) do
        if km.lhs == "i" then
          has_i = true
        end
      end
      assert.is_false(has_i)

      vim.api.nvim_win_close(floating_win, true)
    end)

    it("invokes on_ignore with the finding under the cursor when 'i' is pressed", function()
      local findings = {
        { name = "left-pad", version = "1.3.0", severity = "high", backend = "audit", reason = "..." },
        { name = "colors", version = "1.4.0", severity = "critical", backend = "audit", reason = "..." },
      }
      local ignored
      ui.show(findings, {
        on_ignore = function(finding)
          ignored = finding
        end,
      })

      local wins = vim.api.nvim_list_wins()
      local floating_win = wins[#wins]
      vim.api.nvim_win_set_cursor(floating_win, { 2, 0 })

      local bufnr = vim.api.nvim_win_get_buf(floating_win)
      local buf_keymaps = vim.api.nvim_buf_get_keymap(bufnr, "n")
      local i_keymap
      for _, km in ipairs(buf_keymaps) do
        if km.lhs == "i" then
          i_keymap = km
        end
      end
      assert.is_not_nil(i_keymap)
      i_keymap.callback()

      assert.is_not_nil(ignored)
      assert.are.equal("colors", ignored.name)

      vim.api.nvim_win_close(floating_win, true)
    end)

    it("removes the line from the window when on_ignore returns true", function()
      local findings = {
        { name = "left-pad", version = "1.3.0", severity = "high", backend = "audit", reason = "..." },
        { name = "colors", version = "1.4.0", severity = "critical", backend = "audit", reason = "..." },
      }
      ui.show(findings, {
        on_ignore = function()
          return true
        end,
      })

      local wins = vim.api.nvim_list_wins()
      local floating_win = wins[#wins]
      local bufnr = vim.api.nvim_win_get_buf(floating_win)
      vim.api.nvim_win_set_cursor(floating_win, { 1, 0 })

      local i_keymap
      for _, km in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
        if km.lhs == "i" then
          i_keymap = km
        end
      end
      i_keymap.callback()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.are.equal(1, #lines)
      assert.matches("colors", lines[1])
      assert.is_false(vim.bo[bufnr].modifiable)

      vim.api.nvim_win_close(floating_win, true)
    end)

    it("keeps the line in the window when on_ignore returns false", function()
      local findings = {
        { name = "left-pad", version = "1.3.0", severity = "high", backend = "audit", reason = "..." },
      }
      ui.show(findings, {
        on_ignore = function()
          return false
        end,
      })

      local wins = vim.api.nvim_list_wins()
      local floating_win = wins[#wins]
      local bufnr = vim.api.nvim_win_get_buf(floating_win)

      local i_keymap
      for _, km in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
        if km.lhs == "i" then
          i_keymap = km
        end
      end
      i_keymap.callback()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.are.equal(1, #lines)

      vim.api.nvim_win_close(floating_win, true)
    end)
  end)
end)
