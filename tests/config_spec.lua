-- tests/config_spec.lua
describe("impostor-pkg.config", function()
  local config

  before_each(function()
    package.loaded["impostor-pkg.config"] = nil
    config = require("impostor-pkg.config")
  end)

  it("returns sane defaults when setup() is not called", function()
    local resolved = config.get()
    assert.are.equal("auto", resolved.backend)
    assert.is_true(resolved.auto_scan_on_save)
    assert.are.same({}, resolved.ignore)
    assert.are.equal("low", resolved.min_severity)
  end)

  it("overrides backend when a valid value is provided", function()
    config.setup({ backend = "socket" })
    assert.are.equal("socket", config.get().backend)
  end)

  it("errors when backend is not one of auto/socket/audit", function()
    assert.has_error(function()
      config.setup({ backend = "bogus" })
    end)
  end)

  it("errors when min_severity is not a known severity", function()
    assert.has_error(function()
      config.setup({ min_severity = "meh" })
    end)
  end)

  it("errors when ignore is not a list of strings", function()
    assert.has_error(function()
      config.setup({ ignore = { "left-pad", 42 } })
    end)
  end)

  it("errors when auto_scan_on_save is not a boolean", function()
    assert.has_error(function()
      config.setup({ auto_scan_on_save = "yes" })
    end)
  end)

  it("returns sane defaults for the pre-install options", function()
    local resolved = config.get()
    assert.is_true(resolved.auto_scan_on_package_json_save)
    assert.are.equal("high", resolved.confirm_threshold)
  end)

  it("overrides confirm_threshold when a valid value is provided", function()
    config.setup({ confirm_threshold = "critical" })
    assert.are.equal("critical", config.get().confirm_threshold)
  end)

  it("errors when confirm_threshold is not a known severity", function()
    assert.has_error(function()
      config.setup({ confirm_threshold = "meh" })
    end)
  end)

  it(
    "errors when confirm_threshold is 'info' (info is a valid finding severity but not a valid config value)",
    function()
      assert.has_error(function()
        config.setup({ confirm_threshold = "info" })
      end)
    end
  )

  it("errors when auto_scan_on_package_json_save is not a boolean", function()
    assert.has_error(function()
      config.setup({ auto_scan_on_package_json_save = "yes" })
    end)
  end)

  it("returns a sane default for auto_scan_on_startup", function()
    local resolved = config.get()
    assert.is_true(resolved.auto_scan_on_startup)
  end)

  it("overrides auto_scan_on_startup when a valid value is provided", function()
    config.setup({ auto_scan_on_startup = false })
    assert.is_false(config.get().auto_scan_on_startup)
  end)

  it("errors when auto_scan_on_startup is not a boolean", function()
    assert.has_error(function()
      config.setup({ auto_scan_on_startup = "yes" })
    end)
  end)

  describe("add_ignore", function()
    it("appends a package name to the currently resolved ignore list", function()
      config.setup({ ignore = { "left-pad" } })
      config.add_ignore("colors")
      assert.are.same({ "left-pad", "colors" }, config.get().ignore)
    end)

    it("is idempotent — does not add the same name twice", function()
      config.setup({ ignore = { "left-pad" } })
      config.add_ignore("left-pad")
      assert.are.same({ "left-pad" }, config.get().ignore)
    end)

    it("works even when setup() was never called", function()
      config.add_ignore("colors")
      assert.are.same({ "colors" }, config.get().ignore)
    end)
  end)

  it("does not alias a user-supplied ignore table after setup()", function()
    local user_ignore = { "left-pad" }
    config.setup({ ignore = user_ignore })
    table.insert(user_ignore, "colors")
    assert.are.same({ "left-pad" }, config.get().ignore)
  end)

  it("does not accumulate options across repeated setup() calls", function()
    config.setup({ ignore = { "left-pad" } })
    config.setup({ backend = "audit" })
    local resolved = config.get()
    assert.are.equal("audit", resolved.backend)
    assert.are.same({}, resolved.ignore)
  end)

  describe("severity_at_least", function()
    it("returns true when severity meets or exceeds the minimum", function()
      assert.is_true(config.severity_at_least("high", "low"))
      assert.is_true(config.severity_at_least("critical", "critical"))
    end)

    it("returns false when severity is below the minimum", function()
      assert.is_false(config.severity_at_least("low", "high"))
    end)

    it("errors on an unknown severity value", function()
      assert.has_error(function()
        config.severity_at_least("bogus", "low")
      end)
    end)

    it("treats 'info' severity findings as below every valid min_severity without erroring", function()
      assert.has_no.errors(function()
        assert.is_false(config.severity_at_least("info", "low"))
      end)
      assert.is_false(config.severity_at_least("info", "moderate"))
      assert.is_false(config.severity_at_least("info", "critical"))
    end)
  end)

  it("errors when min_severity is 'info' (info is a valid finding severity but not a valid config value)", function()
    assert.has_error(function()
      config.setup({ min_severity = "info" })
    end)
  end)
end)
