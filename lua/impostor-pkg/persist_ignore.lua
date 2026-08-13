local M = {}

local SETUP_CALL_PATTERN = "require%([\"']impostor%-pkg[\"']%)%s*%.%s*setup%s*%("

local function read_file(path)
  local fd = io.open(path, "r")
  if not fd then
    return nil
  end
  local contents = fd:read("*a")
  fd:close()
  return contents
end

local function write_file(path, contents)
  local fd = io.open(path, "w")
  if not fd then
    return false
  end
  fd:write(contents)
  fd:close()
  return true
end

-- Byte offset -> 1-indexed line number, for disambiguating multiple matches by near_line.
local function line_of(text, byte_idx)
  local line = 1
  for _ in text:sub(1, byte_idx):gmatch("\n") do
    line = line + 1
  end
  return line
end

-- Finds every `require("impostor-pkg").setup(` occurrence, returning the byte index of each
-- match's opening "(" (the one right after "setup").
local function find_setup_calls(text)
  local calls = {}
  local search_from = 1
  while true do
    local match_start, match_end = text:find(SETUP_CALL_PATTERN, search_from)
    if not match_start then
      break
    end
    table.insert(calls, match_end) -- match_end is the position of the opening "("
    search_from = match_end + 1
  end
  return calls
end

-- Given the byte index of an opening "(" or "{", finds the index of its matching closing
-- ")" or "}" via depth counting. Returns nil if unbalanced.
local function find_matching(text, open_idx, open_char, close_char)
  local depth = 0
  local i = open_idx
  local len = #text
  while i <= len do
    local c = text:sub(i, i)
    if c == open_char then
      depth = depth + 1
    elseif c == close_char then
      depth = depth - 1
      if depth == 0 then
        return i
      end
    end
    i = i + 1
  end
  return nil
end

-- Text to insert right after an ignore table's opening "{". Multi-line tables (a newline soon
-- after "{") get the entry on its own indented line; single-line tables get it inline.
local function insertion_for_ignore_table(text, brace_idx, escaped_name)
  local after = text:sub(brace_idx + 1)
  if after:match("^%s*\n") then
    return '\n    "' .. escaped_name .. '",'
  end
  return ' "' .. escaped_name .. '",'
end

function M.add(file_path, near_line, package_name)
  local text = read_file(file_path)
  if not text then
    return false, "impostor-pkg: could not read " .. file_path
  end

  local calls = find_setup_calls(text)
  if #calls == 0 then
    return false, 'impostor-pkg: could not find require("impostor-pkg").setup(...) in ' .. file_path
  end

  local paren_idx = calls[1]
  if #calls > 1 then
    if not near_line then
      return false,
        "impostor-pkg: found multiple impostor-pkg setup() calls in " .. file_path .. ", not sure which to edit"
    end
    local best_distance = math.huge
    for _, candidate in ipairs(calls) do
      local distance = math.abs(line_of(text, candidate) - near_line)
      if distance < best_distance then
        best_distance = distance
        paren_idx = candidate
      end
    end
  end

  local close_paren_idx = find_matching(text, paren_idx, "(", ")")
  if not close_paren_idx then
    return false, "impostor-pkg: setup(...) call in " .. file_path .. " has no matching closing paren"
  end

  local call_body = text:sub(paren_idx, close_paren_idx)
  local escaped_name = package_name:gsub('"', '\\"')
  local _, ignore_brace_rel_end = call_body:find("ignore%s*=%s*{")

  if ignore_brace_rel_end then
    local ignore_brace_idx = paren_idx + ignore_brace_rel_end - 1
    local insert_text = insertion_for_ignore_table(text, ignore_brace_idx, escaped_name)
    local new_text = text:sub(1, ignore_brace_idx) .. insert_text .. text:sub(ignore_brace_idx + 1)

    if not write_file(file_path, new_text) then
      return false, "impostor-pkg: could not write " .. file_path
    end
    return true, 'impostor-pkg: added "' .. package_name .. '" to ignore in ' .. file_path
  end

  -- No ignore table yet: insert a new `ignore = { "name" },` field right after the options
  -- table's own opening "{", if the setup() call takes one as its first/only argument.
  local _, options_brace_rel_end = call_body:find("{")
  if not options_brace_rel_end then
    return false,
      "impostor-pkg: setup(...) call in "
        .. file_path
        .. " doesn't use an inline options table — add `ignore = { \""
        .. package_name
        .. '" }` yourself'
  end
  local options_brace_idx = paren_idx + options_brace_rel_end - 1
  local insert_text = ' ignore = { "' .. escaped_name .. '" },'
  local new_text = text:sub(1, options_brace_idx) .. insert_text .. text:sub(options_brace_idx + 1)

  if not write_file(file_path, new_text) then
    return false, "impostor-pkg: could not write " .. file_path
  end
  return true, 'impostor-pkg: added "' .. package_name .. '" to ignore in ' .. file_path
end

return M
