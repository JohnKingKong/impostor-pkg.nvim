local M = {}

local function escape_pattern(s)
  return (s:gsub("([^%w])", "%%%1"))
end

local function read_file(path)
  local fd = io.open(path, "r")
  if not fd then
    return nil
  end
  local contents = fd:read("*a")
  fd:close()
  return contents
end

function M.parse_declared(package_json_path)
  local contents = read_file(package_json_path)
  if not contents then
    return {}
  end

  local ok, decoded = pcall(vim.json.decode, contents)
  if not ok or type(decoded) ~= "table" then
    return {}
  end

  local declared = {}
  for _, field in ipairs({ "dependencies", "devDependencies" }) do
    if type(decoded[field]) == "table" then
      for name, version in pairs(decoded[field]) do
        declared[name] = version
      end
    end
  end
  return declared
end

local function locked_names_from_npm_lockfile(contents)
  local ok, decoded = pcall(vim.json.decode, contents)
  if not ok or type(decoded) ~= "table" then
    return {}
  end

  local names = {}
  if type(decoded.packages) == "table" then
    for key, _ in pairs(decoded.packages) do
      local name = key:match("node_modules/(@[^/]+/[^/]+)$") or key:match("node_modules/([^/]+)$")
      if name then
        names[name] = true
      end
    end
  end
  if type(decoded.dependencies) == "table" then
    for name, _ in pairs(decoded.dependencies) do
      names[name] = true
    end
  end
  return names
end

-- yarn.lock / pnpm-lock.yaml aren't JSON; rather than parse their custom formats, check one
-- name at a time against a "<name>@" line-start pattern via a lazy __index lookup table.
local function locked_lookup_from_text_lockfile(contents)
  return setmetatable({}, {
    __index = function(_, name)
      local pattern = '^%s*"?' .. escape_pattern(name) .. "@"
      for line in contents:gmatch("[^\r\n]+") do
        if line:match(pattern) then
          return true
        end
      end
      return false
    end,
  })
end

function M.parse_locked(lockfile_path, package_manager)
  local contents = read_file(lockfile_path)
  if not contents then
    return {}
  end

  if package_manager == "npm" then
    return locked_names_from_npm_lockfile(contents)
  end

  return locked_lookup_from_text_lockfile(contents)
end

function M.pending(declared, locked)
  local pending = {}
  for name, version in pairs(declared) do
    if not locked[name] then
      table.insert(pending, { name = name, version = version })
    end
  end
  table.sort(pending, function(a, b)
    return a.name < b.name
  end)
  return pending
end

function M.pending_dependencies(project)
  local declared = M.parse_declared(project.package_json)
  local locked = M.parse_locked(project.lockfile, project.package_manager)
  return M.pending(declared, locked)
end

return M
