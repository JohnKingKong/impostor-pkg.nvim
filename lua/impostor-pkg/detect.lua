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

local home_dir_fn = function()
  return uv.os_homedir()
end

function M._set_home_dir_fn(fn)
  home_dir_fn = fn
end

function M._reset()
  home_dir_fn = function()
    return uv.os_homedir()
  end
end

-- True when `dir` is the home directory itself, or an ancestor of it. Used to stop the upward
-- lockfile search before it can wander into the home directory (or above it) and mistake stray
-- npm/yarn/pnpm files there for a project belonging to some unrelated directory being edited.
local function is_home_or_above(dir, home)
  if not home or home == "" then
    return false
  end
  if dir == home then
    return true
  end
  return home:sub(1, #dir + 1) == dir .. "/"
end

function M.find_project(start_dir)
  local current = start_dir or vim.fn.getcwd()
  local home = home_dir_fn()

  while current and current ~= "" do
    if is_home_or_above(current, home) then
      break
    end

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
