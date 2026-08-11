describe("impostor-pkg.diagnostics", function()
  local diagnostics
  local bufnr
  local path

  before_each(function()
    package.loaded["impostor-pkg.diagnostics"] = nil
    diagnostics = require("impostor-pkg.diagnostics")

    path = vim.fn.tempname() .. "-package.json"
    local fd = assert(io.open(path, "w"))
    fd:write('{\n  "dependencies": {\n    "left-pad": "1.3.0",\n    "colors": "1.4.0"\n  }\n}\n')
    fd:close()

    bufnr = vim.fn.bufadd(path)
    vim.fn.bufload(bufnr)
  end)

  after_each(function()
    diagnostics.clear(path)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    os.remove(path)
  end)

  it("sets a diagnostic on the line declaring the flagged package", function()
    diagnostics.apply(path, {
      { name = "left-pad", severity = "high", backend = "audit", reason = "Prototype Pollution" },
    })

    local diags = vim.diagnostic.get(bufnr, { namespace = diagnostics.NAMESPACE })

    assert.are.equal(1, #diags)
    assert.are.equal(2, diags[1].lnum) -- 0-indexed: line 3 ("left-pad": ...) is index 2
    assert.is_true(diags[1].message:find("Prototype Pollution") ~= nil)
  end)

  it("sets one diagnostic per finding when multiple packages are flagged", function()
    diagnostics.apply(path, {
      { name = "left-pad", severity = "high", backend = "audit", reason = "r1" },
      { name = "colors", severity = "critical", backend = "audit", reason = "r2" },
    })

    local diags = vim.diagnostic.get(bufnr, { namespace = diagnostics.NAMESPACE })
    assert.are.equal(2, #diags)
  end)

  it("maps severity to vim.diagnostic.severity levels", function()
    diagnostics.apply(path, { { name = "left-pad", severity = "critical", backend = "audit", reason = "r" } })
    local diags = vim.diagnostic.get(bufnr, { namespace = diagnostics.NAMESPACE })
    assert.are.equal(vim.diagnostic.severity.ERROR, diags[1].severity)
  end)

  it("skips a finding whose package name is not found in the buffer", function()
    diagnostics.apply(path, { { name = "does-not-exist", severity = "high", backend = "audit", reason = "r" } })
    local diags = vim.diagnostic.get(bufnr, { namespace = diagnostics.NAMESPACE })
    assert.are.equal(0, #diags)
  end)

  it("is a no-op when the package.json path has no open buffer", function()
    -- should not error even though nothing is loaded for this path
    diagnostics.apply(
      "/tmp/does-not-exist/package.json",
      { { name = "x", severity = "low", backend = "audit", reason = "r" } }
    )
  end)

  it("clear() removes all diagnostics set by apply()", function()
    diagnostics.apply(path, { { name = "left-pad", severity = "high", backend = "audit", reason = "r" } })
    diagnostics.clear(path)
    local diags = vim.diagnostic.get(bufnr, { namespace = diagnostics.NAMESPACE })
    assert.are.equal(0, #diags)
  end)

  it("replaces previous diagnostics rather than accumulating on repeated apply() calls", function()
    diagnostics.apply(path, { { name = "left-pad", severity = "high", backend = "audit", reason = "r1" } })
    diagnostics.apply(path, { { name = "colors", severity = "low", backend = "audit", reason = "r2" } })
    local diags = vim.diagnostic.get(bufnr, { namespace = diagnostics.NAMESPACE })
    assert.are.equal(1, #diags)
    assert.is_true(diags[1].message:find("r2") ~= nil)
  end)
end)
