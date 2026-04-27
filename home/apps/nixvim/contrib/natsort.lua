-- natsort.lua
--
-- A Lua implementation of natural sort order.
-- This is a port of the C implementation from https://github.com/sourcefrog/natsort
-- adapted from a Zig implementation from https://tangled.sh/@rockorager.dev/lsr/blob/main/src/natord.zig

local M = {}

-- Helper to check if a character is a whitespace character.
local function is_space(char)
  -- In Lua, sub on an out-of-bounds index returns an empty string.
  -- string.match on an empty string returns nil.
  return char and char:match("%s")
end

-- Helper to check if a character is a digit.
local function is_digit(char)
  return char and char:match("%d")
end

-- Corresponds to Zig's compareLeft.
-- Compares two number strings lexicographically. Used for numbers with leading zeros.
local function compare_left(a_num, b_num)
  if a_num < b_num then
    return -1 -- lt
  elseif a_num > b_num then
    return 1 -- gt
  else
    return 0 -- eq
  end
end

-- Corresponds to a corrected version of Zig's compareRight.
-- Compares two number strings numerically (length first, then value).
local function compare_right(a_num, b_num)
  -- The longest run of digits wins.
  if #a_num < #b_num then
    return -1 -- lt
  elseif #a_num > #b_num then
    return 1 -- gt
  end

  -- If lengths are equal, the greater value wins.
  if a_num < b_num then
    return -1 -- lt
  elseif a_num > b_num then
    return 1 -- gt
  end

  return 0 -- eq
end

-- The main comparison logic. It iterates through both strings, handling
-- character and number segments appropriately.
-- Returns -1 (lt), 0 (eq), or 1 (gt).
local function nat_order(a, b, fold_case)
  local ai, bi = 1, 1
  local len_a, len_b = #a, #b

  while true do
    local ca_char = a:sub(ai, ai)
    local cb_char = b:sub(bi, bi)

    -- Skip all leading whitespace segments in both strings
    while is_space(ca_char) do
      ai = ai + 1
      ca_char = a:sub(ai, ai)
    end
    while is_space(cb_char) do
      bi = bi + 1
      cb_char = b:sub(bi, bi)
    end

    -- After skipping whitespace, get current characters for comparison
    ca_char = a:sub(ai, ai)
    cb_char = b:sub(bi, bi)

    -- If both characters are digits, handle as a numeric segment
    if is_digit(ca_char) and is_digit(cb_char) then
      -- A number starting with '0' is treated as "fractional" and compared lexicographically
      local fractional = (ca_char == "0" or cb_char == "0")

      -- Find the end of the number block in string 'a'
      local a_num_end = ai
      while is_digit(a:sub(a_num_end + 1, a_num_end + 1)) do
        a_num_end = a_num_end + 1
      end

      -- Find the end of the number block in string 'b'
      local b_num_end = bi
      while is_digit(b:sub(b_num_end + 1, b_num_end + 1)) do
        b_num_end = b_num_end + 1
      end

      local a_num_slice = a:sub(ai, a_num_end)
      local b_num_slice = b:sub(bi, b_num_end)

      local result
      if fractional then
        result = compare_left(a_num_slice, b_num_slice)
      else
        result = compare_right(a_num_slice, b_num_slice)
      end

      if result ~= 0 then
        return result
      end

      -- If numbers are equivalent (e.g., "01" vs "1"), continue comparison after them
      ai = a_num_end + 1
      bi = b_num_end + 1
    else
      -- Standard character comparison
      if ai > len_a and bi > len_b then
        return 0
      end -- Both strings ended
      if ai > len_a then
        return -1
      end -- String 'a' is a prefix of 'b'
      if bi > len_b then
        return 1
      end -- String 'b' is a prefix of 'a'

      if fold_case then
        ca_char = ca_char:upper()
        cb_char = cb_char:upper()
      end

      if ca_char < cb_char then
        return -1
      end
      if ca_char > cb_char then
        return 1
      end

      -- Characters are equal, advance to the next
      ai = ai + 1
      bi = bi + 1
    end
  end
end

--- Compares two strings using natural sort order.
-- @param a The first string.
-- @param b The second string.
-- @return number -1 if a < b, 0 if a == b, 1 if a > b.
function M.order(a, b)
  return nat_order(a, b, false)
end

--- Compares two strings using case-insensitive natural sort order.
-- @param a The first string.
-- @param b The second string.
-- @return number -1 if a < b, 0 if a == b, 1 if a > b.
function M.orderIgnoreCase(a, b)
  return nat_order(a, b, true)
end

return M
