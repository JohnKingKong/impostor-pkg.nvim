local function make_tmp_dir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return dir
end

local function write_file(path, contents)
  local fd = assert(io.open(path, "w"))
  fd:write(contents)
  fd:close()
end

local function read_file(path)
  local fd = assert(io.open(path, "r"))
  local contents = fd:read("*a")
  fd:close()
  return contents
end

describe("impostor-pkg.persist_ignore", function()
  local persist_ignore

  before_each(function()
    package.loaded["impostor-pkg.persist_ignore"] = nil
    persist_ignore = require("impostor-pkg.persist_ignore")
  end)

  describe("inserting into an existing single-line ignore table", function()
    it("inserts the new name after the opening brace", function()
      local dir = make_tmp_dir()
      local path = dir .. "/plugin.lua"
      write_file(
        path,
        'return {\n  "johnkingkong/impostor-pkg.nvim",\n  config = function()\n'
          .. '    require("impostor-pkg").setup({ ignore = { "left-pad" } })\n  end,\n}\n'
      )

      local ok, message = persist_ignore.add(path, 4, "colors")

      assert.is_true(ok)
      assert.matches("colors", message)
      assert.matches('ignore = { "colors", "left%-pad" } }', read_file(path))
    end)

    it("inserts into an empty ignore table", function()
      local dir = make_tmp_dir()
      local path = dir .. "/plugin.lua"
      write_file(path, 'require("impostor-pkg").setup({ ignore = {} })\n')

      local ok = persist_ignore.add(path, 1, "colors")

      assert.is_true(ok)
      assert.matches('ignore = { "colors",} }', read_file(path))
    end)
  end)

  it("inserts into a multi-line ignore table on its own line", function()
    local dir = make_tmp_dir()
    local path = dir .. "/plugin.lua"
    write_file(path, 'require("impostor-pkg").setup({\n  ignore = {\n    "left-pad",\n  },\n})\n')

    local ok = persist_ignore.add(path, 1, "colors")

    assert.is_true(ok)
    local contents = read_file(path)
    assert.matches('ignore = {\n%s*"colors",\n%s*"left%-pad",', contents)
  end)

  it("adds an ignore field when the setup() call has no ignore table yet", function()
    local dir = make_tmp_dir()
    local path = dir .. "/plugin.lua"
    write_file(path, 'require("impostor-pkg").setup({ backend = "audit" })\n')

    local ok, message = persist_ignore.add(path, 1, "colors")

    assert.is_true(ok)
    assert.matches("colors", message)
    local contents = read_file(path)
    assert.matches('ignore = { "colors" }', contents)
    assert.matches('backend = "audit"', contents) -- existing content preserved
  end)

  it("fails without touching the file when setup() takes no inline table", function()
    local dir = make_tmp_dir()
    local path = dir .. "/plugin.lua"
    local original = 'local opts = my_opts\nrequire("impostor-pkg").setup(opts)\n'
    write_file(path, original)

    local ok, message = persist_ignore.add(path, 2, "colors")

    assert.is_false(ok)
    assert.is_string(message)
    assert.are.equal(original, read_file(path))
  end)

  it('fails without touching the file when require("impostor-pkg").setup( is not found', function()
    local dir = make_tmp_dir()
    local path = dir .. "/plugin.lua"
    local original = 'require("some-other-plugin").setup({})\n'
    write_file(path, original)

    local ok, message = persist_ignore.add(path, 1, "colors")

    assert.is_false(ok)
    assert.is_string(message)
    assert.are.equal(original, read_file(path))
  end)

  it("disambiguates multiple setup() calls in one file by picking the one nearest near_line", function()
    local dir = make_tmp_dir()
    local path = dir .. "/plugin.lua"
    write_file(
      path,
      "if false then\n"
        .. '  require("impostor-pkg").setup({ ignore = { "unrelated" } })\n'
        .. "end\n"
        .. 'require("impostor-pkg").setup({ ignore = { "left-pad" } })\n'
    )

    local ok = persist_ignore.add(path, 5, "colors")

    assert.is_true(ok)
    local contents = read_file(path)
    assert.matches('"unrelated"', contents) -- first call untouched
    assert.matches('ignore = { "colors", "left%-pad" }', contents) -- second call updated
  end)

  it("fails without touching the file when the target file does not exist", function()
    local ok, message = persist_ignore.add("/nonexistent/plugin.lua", 1, "colors")

    assert.is_false(ok)
    assert.is_string(message)
  end)
end)
