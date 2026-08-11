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

    assert.has_no.errors(function()
      impostor_pkg.check()
    end)
  end)
end)
