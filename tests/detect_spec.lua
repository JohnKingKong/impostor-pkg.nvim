local function make_tmp_dir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return dir
end

local function write_file(path, contents)
  local fd = assert(io.open(path, "w"))
  fd:write(contents or "{}")
  fd:close()
end

describe("impostor-pkg.detect", function()
  local detect

  before_each(function()
    package.loaded["impostor-pkg.detect"] = nil
    detect = require("impostor-pkg.detect")
  end)

  it("finds an npm project from a package-lock.json in the given directory", function()
    local dir = make_tmp_dir()
    write_file(dir .. "/package.json")
    write_file(dir .. "/package-lock.json")

    local project = detect.find_project(dir)

    assert.is_not_nil(project)
    assert.are.equal("npm", project.package_manager)
    assert.are.equal(dir .. "/package-lock.json", project.lockfile)
    assert.are.equal(dir .. "/package.json", project.package_json)
    assert.are.equal(dir, project.root)
  end)

  it("finds a yarn project from yarn.lock", function()
    local dir = make_tmp_dir()
    write_file(dir .. "/package.json")
    write_file(dir .. "/yarn.lock")

    local project = detect.find_project(dir)

    assert.are.equal("yarn", project.package_manager)
  end)

  it("finds a pnpm project from pnpm-lock.yaml", function()
    local dir = make_tmp_dir()
    write_file(dir .. "/package.json")
    write_file(dir .. "/pnpm-lock.yaml")

    local project = detect.find_project(dir)

    assert.are.equal("pnpm", project.package_manager)
  end)

  it("walks up parent directories to find the lockfile", function()
    local dir = make_tmp_dir()
    write_file(dir .. "/package.json")
    write_file(dir .. "/package-lock.json")
    local nested = dir .. "/src/components"
    vim.fn.mkdir(nested, "p")

    local project = detect.find_project(nested)

    assert.are.equal(dir, project.root)
  end)

  it("returns nil when no lockfile exists up to the filesystem root", function()
    local dir = make_tmp_dir()

    local project = detect.find_project(dir)

    assert.is_nil(project)
  end)

  it("prefers the nearest lockfile over a farther ancestor's lockfile", function()
    local dir = make_tmp_dir()
    write_file(dir .. "/package.json")
    write_file(dir .. "/package-lock.json")
    local nested = dir .. "/packages/app"
    vim.fn.mkdir(nested, "p")
    write_file(nested .. "/package.json")
    write_file(nested .. "/yarn.lock")

    local project = detect.find_project(nested)

    assert.are.equal(nested, project.root)
    assert.are.equal("yarn", project.package_manager)
  end)
end)
