-- tests/backends/socket_spec.lua
describe("impostor-pkg.backends.socket", function()
  local socket

  before_each(function()
    package.loaded["impostor-pkg.backends.socket"] = nil
    socket = require("impostor-pkg.backends.socket")
  end)

  describe("command_for", function()
    it("builds a scan command for the given project root", function()
      assert.are.same({ "socket", "scan", "create", "/tmp/proj", "--json" }, socket.command_for("/tmp/proj"))
    end)
  end)

  describe("parse", function()
    it("extracts findings from components with alerts", function()
      local stdout = vim.json.encode({
        components = {
          {
            type = "npm",
            name = "left-pad",
            version = "1.3.0",
            alerts = {
              { type = "knownVulnerability", severity = "high", description = "Prototype Pollution" },
            },
          },
        },
      })

      local findings = socket.parse(stdout)

      assert.are.equal(1, #findings)
      assert.are.equal("left-pad", findings[1].name)
      assert.are.equal("1.3.0", findings[1].version)
      assert.are.equal("high", findings[1].severity)
      assert.are.equal("socket", findings[1].backend)
      assert.are.equal("Prototype Pollution", findings[1].reason)
    end)

    it("produces one finding per alert when a component has multiple alerts", function()
      local stdout = vim.json.encode({
        components = {
          {
            name = "left-pad",
            version = "1.3.0",
            alerts = {
              { type = "malware", severity = "critical", description = "Known malware" },
              { type = "typosquat", severity = "high", description = "Typosquat of leftpad" },
            },
          },
        },
      })

      local findings = socket.parse(stdout)

      assert.are.equal(2, #findings)
      assert.are.equal("critical", findings[1].severity)
      assert.are.equal("high", findings[2].severity)
    end)

    it("skips components without alerts", function()
      local stdout = vim.json.encode({ components = { { name = "left-pad", version = "1.3.0" } } })
      assert.are.same({}, socket.parse(stdout))
    end)

    it("returns an empty list for malformed JSON", function()
      assert.are.same({}, socket.parse("not json"))
    end)

    it("returns an empty list when components is missing", function()
      assert.are.same({}, socket.parse(vim.json.encode({})))
    end)

    it("falls back to the alert type when description is missing", function()
      local stdout = vim.json.encode({
        components = { { name = "left-pad", alerts = { { type = "malware", severity = "critical" } } } },
      })

      local findings = socket.parse(stdout)

      assert.are.equal("malware", findings[1].reason)
    end)
  end)

  describe("is_installed", function()
    it("returns false when the socket binary is not on PATH", function()
      -- fixture-independent: the CI runner never has `socket` installed
      assert.is_false(socket.is_installed())
    end)
  end)

  describe("is_available", function()
    it("returns false when not installed regardless of authentication", function()
      assert.is_false(socket.is_available())
    end)
  end)
end)
