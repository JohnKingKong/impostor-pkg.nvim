local function make_tmp_dir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return dir
end

local function write_file(path, contents)
  local fd = assert(io.open(path, "w"))
  fd:write(contents or "")
  fd:close()
end

describe("impostor-pkg.preinstall", function()
  local preinstall

  before_each(function()
    package.loaded["impostor-pkg.preinstall"] = nil
    preinstall = require("impostor-pkg.preinstall")
  end)

  describe("parse_declared", function()
    it("merges dependencies and devDependencies", function()
      local dir = make_tmp_dir()
      local path = dir .. "/package.json"
      write_file(
        path,
        vim.json.encode({
          dependencies = { ["left-pad"] = "^1.3.0" },
          devDependencies = { ["eslint"] = "^8.0.0" },
        })
      )

      local declared = preinstall.parse_declared(path)

      assert.are.equal("^1.3.0", declared["left-pad"])
      assert.are.equal("^8.0.0", declared["eslint"])
    end)

    it("returns an empty table when the file doesn't exist", function()
      local declared = preinstall.parse_declared("/tmp/impostor-pkg-does-not-exist/package.json")
      assert.are.same({}, declared)
    end)
  end)

  describe("parse_locked", function()
    it("reads locked package names from an npm v2/v3 lockfile's packages field", function()
      local dir = make_tmp_dir()
      local path = dir .. "/package-lock.json"
      write_file(
        path,
        vim.json.encode({
          packages = {
            [""] = {},
            ["node_modules/left-pad"] = { version = "1.3.0" },
            ["node_modules/@scope/pkg"] = { version = "2.0.0" },
          },
        })
      )

      local locked = preinstall.parse_locked(path, "npm")

      assert.is_true(locked["left-pad"])
      assert.is_true(locked["@scope/pkg"])
      assert.is_falsy(locked["not-locked"])
    end)

    it("matches package names at the start of a yarn.lock entry line", function()
      local dir = make_tmp_dir()
      local path = dir .. "/yarn.lock"
      write_file(path, '"left-pad@^1.3.0":\n  version "1.3.0"\n')

      local locked = preinstall.parse_locked(path, "yarn")

      assert.is_true(locked["left-pad"])
      assert.is_falsy(locked["not-locked"])
    end)

    it("matches package names at the start of a pnpm-lock.yaml entry line", function()
      local dir = make_tmp_dir()
      local path = dir .. "/pnpm-lock.yaml"
      write_file(path, "packages:\n  left-pad@1.3.0:\n    resolution: {integrity: sha512-x}\n")

      local locked = preinstall.parse_locked(path, "pnpm")

      assert.is_true(locked["left-pad"])
      assert.is_falsy(locked["not-locked"])
    end)

    it("returns an empty table when the lockfile doesn't exist", function()
      local locked = preinstall.parse_locked("/tmp/impostor-pkg-does-not-exist/package-lock.json", "npm")
      assert.are.same({}, locked)
    end)
  end)

  describe("pending", function()
    it("returns declared names missing from locked, sorted by name", function()
      local declared = { ["zeta"] = "^1.0.0", ["alpha"] = "^2.0.0", ["left-pad"] = "^1.3.0" }
      local locked = { ["left-pad"] = true }

      local pending = preinstall.pending(declared, locked)

      assert.are.equal(2, #pending)
      assert.are.equal("alpha", pending[1].name)
      assert.are.equal("zeta", pending[2].name)
    end)

    it("returns an empty list when everything declared is already locked", function()
      local declared = { ["left-pad"] = "^1.3.0" }
      local locked = { ["left-pad"] = true }

      assert.are.same({}, preinstall.pending(declared, locked))
    end)
  end)

  describe("pending_dependencies", function()
    it("combines parse_declared, parse_locked and pending for a project", function()
      local dir = make_tmp_dir()
      write_file(
        dir .. "/package.json",
        vim.json.encode({
          dependencies = { ["left-pad"] = "^1.3.0", ["new-dep"] = "^1.0.0" },
        })
      )
      write_file(
        dir .. "/package-lock.json",
        vim.json.encode({
          packages = { ["node_modules/left-pad"] = { version = "1.3.0" } },
        })
      )

      local pending = preinstall.pending_dependencies({
        package_json = dir .. "/package.json",
        lockfile = dir .. "/package-lock.json",
        package_manager = "npm",
      })

      assert.are.equal(1, #pending)
      assert.are.equal("new-dep", pending[1].name)
    end)
  end)
end)
