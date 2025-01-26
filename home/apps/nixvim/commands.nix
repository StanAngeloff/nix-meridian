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
  '';
}
