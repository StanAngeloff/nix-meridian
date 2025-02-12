{
  programs.nixvim.extraConfigLua = ''
    -- Send file to freedesktop.org trashcan, depends on `trash` command.
    local function trash(path)
      local result = vim.fn.system('trash ' .. vim.fn.shellescape(path))
      if vim.v.shell_error ~= 0 then
        if vim.fn.isdirectory(path) == 1 then
          error("Trash.PathDeletionError: Could not trash directory: '" .. path .. "'.")
        elseif vim.fn.filereadable(path) == 1 then
          error("Trash.FileDeletionError: Could not trash file '" .. path .. "'.")
        else
          error("Trash.UnknownDeletionError: Could not trash path '" .. path .. "', the path is not readable.")
        end
      end

      local bufnum = vim.fn.bufnr('^' .. path .. '$')
      if vim.fn.buflisted(bufnum) == 1 then
        vim.cmd('bwipeout! ' .. bufnum)
      end
    end

    -- Create the Vim command
    vim.api.nvim_create_user_command('Trash', function(opts)
      if opts.args == "" then
        -- No argument provided, use current buffer's file
        local current_file = vim.fn.expand('%:p')
        if current_file == "" then
          vim.notify("No file in current buffer", vim.log.levels.ERROR)
          return
        end
        trash(current_file)
      else
        -- Argument provided, use that file
        trash(opts.args)
      end
    end, {
      nargs = '?',
      complete = 'file'
    })

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

    vim.api.nvim_create_user_command('Sort', function(opts)
      local start_line = opts.line1 - 1
      local end_line = opts.line2
      local lines = vim.api.nvim_buf_get_lines(0, start_line, end_line, false)
      table.sort(lines, sort_compare_strings)
      vim.api.nvim_buf_set_lines(0, start_line, end_line, false, lines)
    end, { range = true })
  '';
}
