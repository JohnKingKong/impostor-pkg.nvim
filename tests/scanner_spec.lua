describe("impostor-pkg.scanner", function()
  local scanner
  local config

  before_each(function()
    package.loaded["impostor-pkg.scanner"] = nil
    package.loaded["impostor-pkg.config"] = nil
    scanner = require("impostor-pkg.scanner")
    config = require("impostor-pkg.config")
    config.setup({ backend = "audit" })
  end)

  after_each(function()
    scanner._reset()
  end)

  local function stub_project()
    return {
      root = "/tmp/proj",
      package_manager = "npm",
      lockfile = "/tmp/proj/package-lock.json",
      package_json = "/tmp/proj/package.json",
    }
  end

  local function stub_system(stdout, exit_code)
    return function(_cmd, _opts, on_exit)
      on_exit({ code = exit_code or 0, stdout = stdout or "{}", stderr = "" })
    end
  end

  it("reports skipped=true with no project when no lockfile is found", function()
    scanner._set_detect_fn(function()
      return nil
    end)

    local result
    scanner.run({}, function(r)
      result = r
    end)

    assert.is_true(result.ok)
    assert.is_true(result.skipped)
    assert.is_nil(result.project)
  end)

  it("runs the audit backend and returns parsed findings", function()
    scanner._set_detect_fn(stub_project)
    scanner._set_system_fn(stub_system(vim.json.encode({
      vulnerabilities = { ["left-pad"] = { name = "left-pad", severity = "high", via = {} } },
    })))

    local result
    scanner.run({}, function(r)
      result = r
    end)

    assert.is_true(result.ok)
    assert.are.equal(1, #result.findings)
    assert.are.equal("left-pad", result.findings[1].name)
  end)

  it("filters out findings below min_severity", function()
    config.setup({ backend = "audit", min_severity = "high" })
    scanner._set_detect_fn(stub_project)
    scanner._set_system_fn(stub_system(vim.json.encode({
      vulnerabilities = {
        ["left-pad"] = { name = "left-pad", severity = "low", via = {} },
        ["colors"] = { name = "colors", severity = "critical", via = {} },
      },
    })))

    local result
    scanner.run({}, function(r)
      result = r
    end)

    assert.are.equal(1, #result.findings)
    assert.are.equal("colors", result.findings[1].name)
  end)

  it("filters out ignored package names", function()
    config.setup({ backend = "audit", ignore = { "left-pad" } })
    scanner._set_detect_fn(stub_project)
    scanner._set_system_fn(stub_system(vim.json.encode({
      vulnerabilities = { ["left-pad"] = { name = "left-pad", severity = "critical", via = {} } },
    })))

    local result
    scanner.run({}, function(r)
      result = r
    end)

    assert.are.same({}, result.findings)
  end)

  it("skips re-scanning when the lockfile hash is unchanged and force is not set", function()
    local call_count = 0
    scanner._set_detect_fn(stub_project)
    scanner._set_system_fn(function(_cmd, _opts, on_exit)
      call_count = call_count + 1
      on_exit({ code = 0, stdout = "{}", stderr = "" })
    end)
    scanner._set_hash_fn(function(_lockfile)
      return "same-hash"
    end)

    scanner.run({}, function() end)
    local second_result
    scanner.run({}, function(r)
      second_result = r
    end)

    assert.are.equal(1, call_count)
    assert.is_true(second_result.skipped)
  end)

  it("bypasses the cache when force=true even with an unchanged hash", function()
    local call_count = 0
    scanner._set_detect_fn(stub_project)
    scanner._set_system_fn(function(_cmd, _opts, on_exit)
      call_count = call_count + 1
      on_exit({ code = 0, stdout = "{}", stderr = "" })
    end)
    scanner._set_hash_fn(function(_lockfile)
      return "same-hash"
    end)

    scanner.run({}, function() end)
    scanner.run({ force = true }, function() end)

    assert.are.equal(2, call_count)
  end)

  it("returns ok=false with an error message when the CLI exits non-zero and stdout is unparseable", function()
    scanner._set_detect_fn(stub_project)
    scanner._set_system_fn(stub_system("not json", 1))

    local result
    scanner.run({}, function(r)
      result = r
    end)

    assert.is_false(result.ok)
    assert.is_string(result.error)
  end)
end)
