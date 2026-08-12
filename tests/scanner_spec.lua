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

  -- scanner.run's system_fn completion callback runs the rest of the work inside
  -- vim.schedule (so real vim.system callbacks, which fire in a fast-event context, are safe).
  -- Even when the stub invokes on_exit synchronously, the scheduled work is only queued, not
  -- run, by the time scanner.run() returns, so tests must pump the event loop for it.
  local function wait_for(predicate)
    vim.wait(200, predicate, 5)
  end

  local function run_and_wait(opts)
    local result
    scanner.run(opts or {}, function(r)
      result = r
    end)
    wait_for(function()
      return result ~= nil
    end)
    return result
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

    local result = run_and_wait({})

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

    local result = run_and_wait({})

    assert.are.equal(1, #result.findings)
    assert.are.equal("colors", result.findings[1].name)
  end)

  it("filters out ignored package names", function()
    config.setup({ backend = "audit", ignore = { "left-pad" } })
    scanner._set_detect_fn(stub_project)
    scanner._set_system_fn(stub_system(vim.json.encode({
      vulnerabilities = { ["left-pad"] = { name = "left-pad", severity = "critical", via = {} } },
    })))

    local result = run_and_wait({})

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

    -- Wait for the first scan's scheduled completion so it has populated the hash cache
    -- before the second run checks it; otherwise the second call would race the first.
    run_and_wait({})
    local second_result = run_and_wait({})

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

    run_and_wait({})
    run_and_wait({ force = true })

    assert.are.equal(2, call_count)
  end)

  it("returns ok=false with an error message when the CLI exits non-zero and stdout is unparseable", function()
    scanner._set_detect_fn(stub_project)
    scanner._set_system_fn(stub_system("not json", 1))

    local result = run_and_wait({})

    assert.is_false(result.ok)
    assert.is_string(result.error)
  end)

  it("returns ok=false without invoking system_fn when the backend CLI is not available", function()
    local call_count = 0
    scanner._set_detect_fn(function()
      return {
        root = "/tmp/proj",
        package_manager = "not-a-real-package-manager",
        lockfile = "/tmp/proj/package-lock.json",
        package_json = "/tmp/proj/package.json",
      }
    end)
    scanner._set_system_fn(function(_cmd, _opts, on_exit)
      call_count = call_count + 1
      on_exit({ code = 0, stdout = "{}", stderr = "" })
    end)

    local result
    scanner.run({}, function(r)
      result = r
    end)

    assert.is_false(result.ok)
    assert.is_string(result.error)
    assert.are.equal(0, call_count)
  end)

  it("returns ok=false without invoking system_fn when forced socket backend is unavailable", function()
    config.setup({ backend = "socket" })
    local call_count = 0
    scanner._set_detect_fn(stub_project)
    scanner._set_system_fn(function(_cmd, _opts, on_exit)
      call_count = call_count + 1
      on_exit({ code = 0, stdout = "{}", stderr = "" })
    end)

    local result
    scanner.run({}, function(r)
      result = r
    end)

    assert.is_false(result.ok)
    assert.is_string(result.error)
    assert.are.equal(0, call_count)
  end)

  describe("run_preinstall", function()
    -- Deliberately never `package.loaded["impostor-pkg.preinstall"] = nil` here: scanner.lua
    -- holds its own `local preinstall = require(...)` reference captured once at module load.
    -- Re-requiring a fresh copy in this file would create a second, disconnected table that
    -- monkeypatching below wouldn't affect. Instead, grab the same cached table scanner already
    -- uses and restore its field after each test.
    local preinstall = require("impostor-pkg.preinstall")
    local original_pending_dependencies = preinstall.pending_dependencies

    after_each(function()
      preinstall.pending_dependencies = original_pending_dependencies
    end)

    local function run_preinstall_and_wait()
      local result
      scanner.run_preinstall(function(r)
        result = r
      end)
      wait_for(function()
        return result ~= nil
      end)
      return result
    end

    it("reports skipped=true with no project when no lockfile is found", function()
      scanner._set_detect_fn(function()
        return nil
      end)

      local result
      scanner.run_preinstall(function(r)
        result = r
      end)

      assert.is_true(result.ok)
      assert.is_true(result.skipped)
      assert.is_nil(result.project)
    end)

    it("reports skipped=true with an empty pending list when nothing is pending", function()
      scanner._set_detect_fn(stub_project)
      preinstall.pending_dependencies = function()
        return {}
      end

      local result = run_preinstall_and_wait()

      assert.is_true(result.ok)
      assert.is_true(result.skipped)
      assert.is_not_nil(result.project)
      assert.are.same({}, result.pending)
    end)

    it("checks pending deps via socket and filters findings to just those names", function()
      config.setup({ backend = "socket" })
      scanner._set_detect_fn(stub_project)
      preinstall.pending_dependencies = function()
        return { { name = "new-dep", version = "^1.0.0" } }
      end

      local socket_backend = require("impostor-pkg.backends.socket")
      local original_is_available = socket_backend.is_available
      socket_backend.is_available = function()
        return true
      end

      scanner._set_system_fn(stub_system(vim.json.encode({
        components = {
          { name = "new-dep", version = "1.0.0", alerts = { { severity = "high", description = "malware" } } },
          { name = "left-pad", version = "1.3.0", alerts = { { severity = "high", description = "unrelated" } } },
        },
      })))

      local result = run_preinstall_and_wait()
      socket_backend.is_available = original_is_available

      assert.is_true(result.ok)
      assert.are.equal(1, #result.findings)
      assert.are.equal("new-dep", result.findings[1].name)
    end)

    it("resolves the lockfile then audits and filters findings to pending names (npm)", function()
      config.setup({ backend = "audit" })
      scanner._set_detect_fn(stub_project)
      preinstall.pending_dependencies = function()
        return { { name = "new-dep", version = "^1.0.0" } }
      end

      local calls = {}
      scanner._set_system_fn(function(cmd, _opts, on_exit)
        table.insert(calls, cmd)
        if #calls == 1 then
          on_exit({ code = 0, stdout = "", stderr = "" })
        else
          on_exit({
            code = 0,
            stdout = vim.json.encode({
              vulnerabilities = {
                ["new-dep"] = { name = "new-dep", severity = "critical", via = {} },
                ["left-pad"] = { name = "left-pad", severity = "critical", via = {} },
              },
            }),
            stderr = "",
          })
        end
      end)

      local result = run_preinstall_and_wait()

      assert.are.equal(2, #calls)
      assert.are.same({ "npm", "install", "--package-lock-only" }, calls[1])
      assert.are.same({ "npm", "audit", "--json" }, calls[2])
      assert.is_true(result.ok)
      assert.are.equal(1, #result.findings)
      assert.are.equal("new-dep", result.findings[1].name)
    end)

    it("returns ok=false when lockfile-only resolution exits non-zero", function()
      config.setup({ backend = "audit" })
      scanner._set_detect_fn(stub_project)
      preinstall.pending_dependencies = function()
        return { { name = "new-dep", version = "^1.0.0" } }
      end
      scanner._set_system_fn(function(_cmd, _opts, on_exit)
        on_exit({ code = 1, stdout = "", stderr = "network error" })
      end)

      local result = run_preinstall_and_wait()

      assert.is_false(result.ok)
      assert.is_string(result.error)
    end)

    it("reports unchecked pending deps for audit-only yarn projects", function()
      config.setup({ backend = "audit" })
      scanner._set_detect_fn(function()
        return {
          root = "/tmp/proj",
          package_manager = "yarn",
          lockfile = "/tmp/proj/yarn.lock",
          package_json = "/tmp/proj/package.json",
        }
      end)
      preinstall.pending_dependencies = function()
        return { { name = "new-dep", version = "^1.0.0" } }
      end
      local call_count = 0
      scanner._set_system_fn(function(_cmd, _opts, on_exit)
        call_count = call_count + 1
        on_exit({ code = 0, stdout = "{}", stderr = "" })
      end)

      local result = run_preinstall_and_wait()

      assert.is_true(result.ok)
      assert.are.equal(0, call_count)
      assert.are.equal(1, #result.unchecked)
      assert.are.equal("new-dep", result.unchecked[1].name)
      assert.are.same({}, result.findings)
    end)
  end)
end)
