-- tests/backends/audit_spec.lua
describe("impostor-pkg.backends.audit", function()
  local audit

  before_each(function()
    package.loaded["impostor-pkg.backends.audit"] = nil
    audit = require("impostor-pkg.backends.audit")
  end)

  describe("command_for", function()
    it("returns the right CLI invocation per package manager", function()
      assert.are.same({ "npm", "audit", "--json" }, audit.command_for("npm"))
      assert.are.same({ "yarn", "audit", "--json" }, audit.command_for("yarn"))
      assert.are.same({ "pnpm", "audit", "--json" }, audit.command_for("pnpm"))
    end)

    it("returns nil for an unknown package manager", function()
      assert.is_nil(audit.command_for("bun"))
    end)
  end)

  describe("resolve_lockfile_only", function()
    it("returns the lockfile-only resolve command for npm", function()
      assert.are.same({ "npm", "install", "--package-lock-only" }, audit.resolve_lockfile_only("npm"))
    end)

    it("returns the lockfile-only resolve command for pnpm", function()
      assert.are.same({ "pnpm", "install", "--lockfile-only" }, audit.resolve_lockfile_only("pnpm"))
    end)

    it("returns nil for yarn (classic yarn has no lockfile-only mode)", function()
      assert.is_nil(audit.resolve_lockfile_only("yarn"))
    end)

    it("returns nil for an unknown package manager", function()
      assert.is_nil(audit.resolve_lockfile_only("bun"))
    end)

    it("does not let a caller mutate the underlying command table", function()
      local command = audit.resolve_lockfile_only("npm")
      table.insert(command, "--extra-flag")
      assert.are.same({ "npm", "install", "--package-lock-only" }, audit.resolve_lockfile_only("npm"))
    end)
  end)

  describe("parse npm", function()
    it("extracts findings from the npm 7+ vulnerabilities shape", function()
      local stdout = vim.json.encode({
        vulnerabilities = {
          ["left-pad"] = {
            name = "left-pad",
            severity = "high",
            range = "1.3.0",
            via = { { title = "Prototype Pollution", severity = "high" } },
          },
        },
      })

      local findings = audit.parse("npm", stdout)

      assert.are.equal(1, #findings)
      assert.are.equal("left-pad", findings[1].name)
      assert.are.equal("high", findings[1].severity)
      assert.are.equal("audit", findings[1].backend)
      assert.are.equal("Prototype Pollution", findings[1].reason)
    end)

    it("falls back to a generic reason when via has no title", function()
      local stdout = vim.json.encode({
        vulnerabilities = {
          ["left-pad"] = { name = "left-pad", severity = "low", via = { "some-dependency" } },
        },
      })

      local findings = audit.parse("npm", stdout)

      assert.are.equal("known vulnerability", findings[1].reason)
    end)

    it("returns an empty list for malformed JSON", function()
      assert.are.same({}, audit.parse("npm", "not json"))
    end)

    it("returns an empty list when vulnerabilities is missing", function()
      assert.are.same({}, audit.parse("npm", vim.json.encode({ metadata = {} })))
    end)
  end)

  describe("parse yarn", function()
    it("extracts findings from auditAdvisory NDJSON lines", function()
      local line1 = vim.json.encode({ type = "auditSummary", data = {} })
      local line2 = vim.json.encode({
        type = "auditAdvisory",
        data = {
          advisory = {
            module_name = "left-pad",
            severity = "moderate",
            title = "Prototype Pollution",
            vulnerable_versions = "<1.3.0",
          },
        },
      })
      local stdout = line1 .. "\n" .. line2 .. "\n"

      local findings = audit.parse("yarn", stdout)

      assert.are.equal(1, #findings)
      assert.are.equal("left-pad", findings[1].name)
      assert.are.equal("moderate", findings[1].severity)
      assert.are.equal("Prototype Pollution", findings[1].reason)
    end)

    it("skips unparseable lines without erroring", function()
      local stdout = "not json\n" .. vim.json.encode({ type = "auditSummary" })
      assert.are.same({}, audit.parse("yarn", stdout))
    end)
  end)

  describe("parse pnpm", function()
    it("extracts findings from the report.advisories shape", function()
      local stdout = vim.json.encode({
        auditReportVersion = 2,
        report = {
          advisories = {
            ["42"] = { module_name = "left-pad", severity = "critical", title = "Prototype Pollution" },
          },
        },
      })

      local findings = audit.parse("pnpm", stdout)

      assert.are.equal(1, #findings)
      assert.are.equal("left-pad", findings[1].name)
      assert.are.equal("critical", findings[1].severity)
    end)

    it("returns an empty list when report.advisories is missing", function()
      assert.are.same({}, audit.parse("pnpm", vim.json.encode({ auditReportVersion = 2 })))
    end)
  end)

  describe("is_available", function()
    it("returns false for an unknown package manager", function()
      assert.is_false(audit.is_available("bun"))
    end)
  end)
end)
