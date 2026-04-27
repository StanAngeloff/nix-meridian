local function sort_split_delimiters(line)
  local parts = {}
  for part in line:gmatch("[^%-%.]+") do
    table.insert(parts, part)
  end
  return parts
end

local function sort_get_common_prefix_length(parts1, parts2)
  local i = 1
  while i <= #parts1 and i <= #parts2 and parts1[i] == parts2[i] do
    i = i + 1
  end
  return i - 1
end

local function sort_get_common_suffix_length(parts1, parts2, start_idx1, start_idx2)
  local i = 0
  while i < math.min(#parts1 - start_idx1 + 1, #parts2 - start_idx2 + 1) do
    if parts1[#parts1 - i] ~= parts2[#parts2 - i] then
      break
    end
    i = i + 1
  end
  return i
end

local function sort_compare_strings(a, b)
  local parts_a = sort_split_delimiters(a)
  local parts_b = sort_split_delimiters(b)

  local prefix_len = sort_get_common_prefix_length(parts_a, parts_b)
  local suffix_len = sort_get_common_suffix_length(parts_a, parts_b, prefix_len + 1, prefix_len + 1)

  if prefix_len + suffix_len >= math.min(#parts_a, #parts_b) then
    return #parts_a < #parts_b
  end

  local a_mid = parts_a[prefix_len + 1]
  local b_mid = parts_b[prefix_len + 1]

  return a_mid < b_mid
end

vim.api.nvim_create_user_command("Sort", function(opts)
  local start_line = opts.line1 - 1
  local end_line = opts.line2
  local lines = vim.api.nvim_buf_get_lines(0, start_line, end_line, false)
  table.sort(lines, sort_compare_strings)
  vim.api.nvim_buf_set_lines(0, start_line, end_line, false, lines)
end, {
  range = true,
})
