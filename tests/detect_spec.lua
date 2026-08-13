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

  describe("home directory boundary", function()
    after_each(function()
      detect._reset()
    end)

    it("never treats the home directory itself as a project, even if it has a lockfile", function()
      local home = make_tmp_dir()
      write_file(home .. "/package.json")
      write_file(home .. "/package-lock.json")
      detect._set_home_dir_fn(function()
        return home
      end)

      local project = detect.find_project(home)

      assert.is_nil(project)
    end)

    it("does not walk up past the home directory to find an ancestor's lockfile", function()
      local above_home = make_tmp_dir()
      write_file(above_home .. "/package.json")
      write_file(above_home .. "/package-lock.json")
      local home = above_home .. "/home-dir"
      vim.fn.mkdir(home, "p")
      local unrelated_project = home .. "/some-other-repo"
      vim.fn.mkdir(unrelated_project, "p")
      detect._set_home_dir_fn(function()
        return home
      end)

      local project = detect.find_project(unrelated_project)

      assert.is_nil(project)
    end)

    it("still finds a real project nested under the home directory", function()
      local home = make_tmp_dir()
      local project_dir = home .. "/my-project"
      vim.fn.mkdir(project_dir, "p")
      write_file(project_dir .. "/package.json")
      write_file(project_dir .. "/package-lock.json")
      detect._set_home_dir_fn(function()
        return home
      end)

      local project = detect.find_project(project_dir)

      assert.is_not_nil(project)
      assert.are.equal(project_dir, project.root)
    end)

    it("still finds a project starting below a nested directory under home with no lockfile of its own", function()
      local home = make_tmp_dir()
      local project_dir = home .. "/my-project"
      vim.fn.mkdir(project_dir, "p")
      write_file(project_dir .. "/package.json")
      write_file(project_dir .. "/package-lock.json")
      local nested = project_dir .. "/src"
      vim.fn.mkdir(nested, "p")
      detect._set_home_dir_fn(function()
        return home
      end)

      local project = detect.find_project(nested)

      assert.is_not_nil(project)
      assert.are.equal(project_dir, project.root)
    end)
  end)
end)
