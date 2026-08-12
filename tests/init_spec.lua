describe("impostor-pkg.init", function()
  local impostor_pkg
  local scanner

  before_each(function()
    for _, mod in ipairs({ "impostor-pkg", "impostor-pkg.init", "impostor-pkg.config", "impostor-pkg.scanner" }) do
      package.loaded[mod] = nil
    end
    impostor_pkg = require("impostor-pkg")
    scanner = require("impostor-pkg.scanner")
  end)

  after_each(function()
    scanner._reset()
  end)

  it("setup() does not error with no options", function()
    assert.has_no.errors(function()
      impostor_pkg.setup()
    end)
  end)

  it("setup() does not error with valid options", function()
    assert.has_no.errors(function()
      impostor_pkg.setup({ backend = "audit", min_severity = "high" })
    end)
  end)

  it("check() calls scanner.run and does not error when no project is found", function()
    scanner._set_detect_fn(function()
      return nil
    end)

    assert.has_no.errors(function()
      impostor_pkg.check()
    end)
  end)

  it("check() surfaces findings via ui.notify without erroring", function()
    scanner._set_detect_fn(function()
      return {
        root = "/tmp/proj",
        package_manager = "npm",
        lockfile = "/tmp/proj/package-lock.json",
        package_json = "/tmp/proj/package.json",
      }
    end)
    scanner._set_system_fn(function(_cmd, _opts, on_exit)
      on_exit({
        code = 0,
        stdout = vim.json.encode({
          vulnerabilities = { ["left-pad"] = { name = "left-pad", severity = "high", via = {} } },
        }),
        stderr = "",
      })
    end)

    -- scanner.run defers the rest of the pipeline (ui.notify/ui.show/diagnostics.apply) to
    -- vim.schedule, so check() itself cannot observe a downstream error synchronously. Pump the
    -- event loop and use the floating window ui.show opens for non-empty findings as evidence
    -- that ui.notify -> ui.show ran to completion without throwing.
    local wins_before = #vim.api.nvim_list_wins()

    assert.has_no.errors(function()
      impostor_pkg.check()
    end)

    vim.wait(200, function()
      return #vim.api.nvim_list_wins() > wins_before
    end, 5)

    assert.are.equal(wins_before + 1, #vim.api.nvim_list_wins())

    local wins = vim.api.nvim_list_wins()
    vim.api.nvim_win_close(wins[#wins], true)
  end)
end)
