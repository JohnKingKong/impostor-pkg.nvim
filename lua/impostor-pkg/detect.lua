local M = {}

M.LOCKFILES = {
  ["package-lock.json"] = "npm",
  ["yarn.lock"] = "yarn",
  ["pnpm-lock.yaml"] = "pnpm",
}

local uv = vim.uv or vim.loop

local function file_exists(path)
  local stat = uv.fs_stat(path)
  return stat ~= nil and stat.type == "file"
end

local function parent_of(dir)
  local trimmed = dir:gsub("/+$", "")
  local parent = trimmed:match("^(.*)/[^/]+$")
  return parent
end

function M.find_project(start_dir)
  local current = start_dir or vim.fn.getcwd()

  while current and current ~= "" do
    for lockfile_name, package_manager in pairs(M.LOCKFILES) do
      local lockfile_path = current .. "/" .. lockfile_name
      if file_exists(lockfile_path) then
        return {
          root = current,
          package_manager = package_manager,
          lockfile = lockfile_path,
          package_json = current .. "/package.json",
        }
      end
    end

    local parent = parent_of(current)
    if parent == current then
      break
    end
    current = parent
  end

  return nil
end

return M
