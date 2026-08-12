describe("impostor-pkg.init", function()
  local impostor_pkg
  local scanner
  local config

  before_each(function()
    for _, mod in ipairs({ "impostor-pkg", "impostor-pkg.init", "impostor-pkg.config", "impostor-pkg.scanner" }) do
      package.loaded[mod] = nil
    end
    impostor_pkg = require("impostor-pkg")
    scanner = require("impostor-pkg.scanner")
    config = require("impostor-pkg.config")
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

  describe("check_preinstall", function()
    it("does not error when no project is found", function()
      scanner._set_detect_fn(function()
        return nil
      end)

      assert.has_no.errors(function()
        impostor_pkg.check_preinstall()
      end)
    end)

    it("does not error when pending deps are flagged", function()
      scanner._set_detect_fn(function()
        return {
          root = "/tmp/proj",
          package_manager = "npm",
          lockfile = "/tmp/proj/package-lock.json",
          package_json = "/tmp/proj/package.json",
        }
      end)
      -- Reuse the already-cached module (see the run_preinstall describe block in
      -- scanner_spec.lua for why this must not be `package.loaded[...] = nil`'d and
      -- re-required — scanner.lua's own `local preinstall = require(...)` reference would
      -- go stale relative to a freshly-required copy here).
      local preinstall = require("impostor-pkg.preinstall")
      local original_pending_dependencies = preinstall.pending_dependencies
      preinstall.pending_dependencies = function()
        return { { name = "new-dep", version = "^1.0.0" } }
      end
      config.setup({ backend = "audit" })
      scanner._set_system_fn(function(cmd, _opts, on_exit)
        if cmd[1] == "npm" and cmd[3] == "--package-lock-only" then
          on_exit({ code = 0, stdout = "", stderr = "" })
        else
          on_exit({
            code = 0,
            stdout = vim.json.encode({
              vulnerabilities = { ["new-dep"] = { name = "new-dep", severity = "high", via = {} } },
            }),
            stderr = "",
          })
        end
      end)

      assert.has_no.errors(function()
        impostor_pkg.check_preinstall()
      end)

      vim.wait(200, function()
        return true
      end, 5)
      preinstall.pending_dependencies = original_pending_dependencies
    end)
  end)

  describe("install", function()
    -- See the note above check_preinstall's test: reuse the cached module, never re-require it.
    local preinstall = require("impostor-pkg.preinstall")
    local original_pending_dependencies
    local jobstart_calls

    before_each(function()
      original_pending_dependencies = preinstall.pending_dependencies
      jobstart_calls = {}
      impostor_pkg._set_jobstart_fn(function(cmd, opts)
        table.insert(jobstart_calls, { cmd = cmd, opts = opts })
        return 1
      end)
      impostor_pkg._set_confirm_fn(function()
        return 1 -- "Yes"
      end)
    end)

    after_each(function()
      preinstall.pending_dependencies = original_pending_dependencies
      impostor_pkg._reset_install_fns()
    end)

    it("runs the install command directly when nothing is pending", function()
      scanner._set_detect_fn(function()
        return {
          root = "/tmp/proj",
          package_manager = "npm",
          lockfile = "/tmp/proj/package-lock.json",
          package_json = "/tmp/proj/package.json",
        }
      end)
      preinstall.pending_dependencies = function()
        return {}
      end

      impostor_pkg.install()
      vim.wait(200, function()
        return #jobstart_calls > 0
      end, 5)

      assert.are.equal(1, #jobstart_calls)
      assert.are.same({ "npm", "install" }, jobstart_calls[1].cmd)
      assert.are.equal("/tmp/proj", jobstart_calls[1].opts.cwd)
    end)

    it("installs without prompting when no finding meets confirm_threshold", function()
      config.setup({ backend = "audit", confirm_threshold = "high" })
      scanner._set_detect_fn(function()
        return {
          root = "/tmp/proj",
          package_manager = "npm",
          lockfile = "/tmp/proj/package-lock.json",
          package_json = "/tmp/proj/package.json",
        }
      end)
      preinstall.pending_dependencies = function()
        return { { name = "new-dep", version = "^1.0.0" } }
      end
      scanner._set_system_fn(function(cmd, _opts, on_exit)
        if cmd[3] == "--package-lock-only" then
          on_exit({ code = 0, stdout = "", stderr = "" })
        else
          on_exit({
            code = 0,
            stdout = vim.json.encode({
              vulnerabilities = { ["new-dep"] = { name = "new-dep", severity = "low", via = {} } },
            }),
            stderr = "",
          })
        end
      end)
      local confirm_calls = 0
      impostor_pkg._set_confirm_fn(function()
        confirm_calls = confirm_calls + 1
        return 1
      end)

      impostor_pkg.install()
      vim.wait(200, function()
        return #jobstart_calls > 0
      end, 5)

      assert.are.equal(0, confirm_calls)
      assert.are.equal(1, #jobstart_calls)
    end)

    it("prompts and proceeds with install when confirm_threshold is met and the user accepts", function()
      config.setup({ backend = "audit", confirm_threshold = "high" })
      scanner._set_detect_fn(function()
        return {
          root = "/tmp/proj",
          package_manager = "npm",
          lockfile = "/tmp/proj/package-lock.json",
          package_json = "/tmp/proj/package.json",
        }
      end)
      preinstall.pending_dependencies = function()
        return { { name = "new-dep", version = "^1.0.0" } }
      end
      scanner._set_system_fn(function(cmd, _opts, on_exit)
        if cmd[3] == "--package-lock-only" then
          on_exit({ code = 0, stdout = "", stderr = "" })
        else
          on_exit({
            code = 0,
            stdout = vim.json.encode({
              vulnerabilities = { ["new-dep"] = { name = "new-dep", severity = "critical", via = {} } },
            }),
            stderr = "",
          })
        end
      end)
      local confirm_calls = 0
      impostor_pkg._set_confirm_fn(function()
        confirm_calls = confirm_calls + 1
        return 1 -- "Yes"
      end)

      impostor_pkg.install()
      vim.wait(200, function()
        return #jobstart_calls > 0
      end, 5)

      assert.are.equal(1, confirm_calls)
      assert.are.equal(1, #jobstart_calls)
      assert.are.same({ "npm", "install" }, jobstart_calls[1].cmd)
    end)

    it("prompts and skips install when confirm_threshold is met and the user declines", function()
      config.setup({ backend = "audit", confirm_threshold = "high" })
      scanner._set_detect_fn(function()
        return {
          root = "/tmp/proj",
          package_manager = "npm",
          lockfile = "/tmp/proj/package-lock.json",
          package_json = "/tmp/proj/package.json",
        }
      end)
      preinstall.pending_dependencies = function()
        return { { name = "new-dep", version = "^1.0.0" } }
      end
      scanner._set_system_fn(function(cmd, _opts, on_exit)
        if cmd[3] == "--package-lock-only" then
          on_exit({ code = 0, stdout = "", stderr = "" })
        else
          on_exit({
            code = 0,
            stdout = vim.json.encode({
              vulnerabilities = { ["new-dep"] = { name = "new-dep", severity = "critical", via = {} } },
            }),
            stderr = "",
          })
        end
      end)
      local confirm_calls = 0
      impostor_pkg._set_confirm_fn(function()
        confirm_calls = confirm_calls + 1
        return 2 -- "No"
      end)

      impostor_pkg.install()
      vim.wait(200, function()
        return confirm_calls > 0
      end, 5)

      assert.are.equal(1, confirm_calls)
      assert.are.equal(0, #jobstart_calls)
    end)
  end)
end)
