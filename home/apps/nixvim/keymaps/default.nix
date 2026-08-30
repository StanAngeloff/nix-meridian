let
  common = import ./common.nix;

  toNixvim =
    {
      key,
      modes,
      action,
      desc ? null,
      ...
    }:
    map (m: {
      inherit key action;
      mode = [ m ];
      options = {
        silent = true;
      }
      // (if desc != null then { inherit desc; } else { });
    }) modes;

  expandedCommon = builtins.concatMap toNixvim common.keymaps;
in
{
  imports = [ ./plugins.nix ];

  programs.nixvim.globals.mapleader = common.leader;

  programs.nixvim.keymaps = expandedCommon ++ [
    # nixfmt: off
    { key = "Q"; mode = [ "n" ]; action = ":windo normal ZZ<CR>"; options.silent = true; options.desc = "Q for 'Q'uit, 'Ex' mode has received zero use"; }
    { key = "Q"; mode = [ "v" ]; action = "<Esc>:windo normal ZZ<CR>"; options.silent = true; }
    { key = "<Return>"; mode = [ "n" ]; action = ":w<CR>"; options.desc = "Frantic <C-S> are now hectic <Return>s"; }
    { key = "<Return>"; mode = [ "v" ]; action = ":<C-U>w<CR>gv"; }
    { key = "<F1>"; mode = [ "n" ]; action = ":setlocal nospell! nospell?<CR>"; options.silent = true; options.desc = "Toggle spell-checking"; }
    { key = "<F2>"; mode = [ "n" ]; action = ":setlocal invpaste paste?<CR>"; options.silent = true; options.desc = "Toggle paste-mode"; }
    { key = "<F3>"; mode = [ "n" ]; action = ":setlocal wrap! wrap?<CR>"; options.silent = true; options.desc = "Toggle long line wrap"; }
    { key = "<F4>"; mode = [ "n" ]; action = ":setlocal list! list?<CR>"; options.silent = true; options.desc = "Toggle list characters"; }
    { key = "<F5>"; mode = [ "n" ]; action = ":w<CR>:call system('tmux send-keys -t ' . shellescape(g:tmux_target) . ' \"q\"')<CR>:sleep 100m<CR>:call system('tmux send-keys -t ' . shellescape(g:tmux_target) . ' \"^C\"')<CR>:sleep 100m<CR>:call system('tmux send-keys -Rt ' . shellescape(g:tmux_target) . ' \"^U\" \"^L\" ' . shellescape(g:tmux_command) . ' \"Enter\"')<CR>"; options.silent = true; }
    { key = "<F5>"; mode = [ "i" ]; action = "<Esc><F5>a"; options.silent = true; }
    { key = "<leader>tn"; mode = [ "n" ]; action = ":tabnew<CR>"; options.desc = "Create a new tab"; }
    { key = "<leader>tm"; mode = [ "n" ]; action = ":tabmove"; options.desc = "Move the current tab"; }
    { key = "<leader>te"; mode = [ "n" ]; action = "':tabedit '"; options.expr = true; }
    # Navigation
    { key = "<C-J>"; mode = [ "n" ]; action = "gt"; options.silent = true; options.desc = "Switch to the next tab"; }
    { key = "<C-K>"; mode = [ "n" ]; action = "gT"; options.silent = true; options.desc = "Switch to the previous tab"; }
    # Quick buffer whitespace changes
    { key = "<leader>w2"; mode = [ "n" ]; action = ":setlocal tabstop=2<CR>:setlocal shiftwidth=2<CR>"; }
    { key = "<leader>w4"; mode = [ "n" ]; action = ":setlocal tabstop=4<CR>:setlocal shiftwidth=4<CR>"; }
    { key = "<leader>w8"; mode = [ "n" ]; action = ":setlocal tabstop=8<CR>:setlocal shiftwidth=8<CR>"; }
    { key = "<leader>w<Tab>"; mode = [ "n" ]; action = ":setlocal noexpandtab<CR>:retab<CR>:echo 'expandtab'<CR>"; options.silent = true; }
    { key = "<leader>w<Space>"; mode = [ "n" ]; action = ":setlocal expandtab<CR>:retab<CR>:echo 'noexpandtab'<CR>"; options.silent = true; }
    # nixfmt: on

    # Jump to the first non-whitespace character on the line or the beginning of the line.
    {
      key = "0";
      mode = [
        "n"
        "v"
      ];
      options.expr = true;
      action.__raw = ''
        function()
          local line = vim.fn.getline(".")
          local col = vim.fn.col(".")
          local before = line:sub(1, col)
          if before:match("^%s+%S$") then
            return "0"
          end
          return "^"
        end
      '';
    }

    # Strip trailing whitespace.
    {
      key = "<leader>W";
      mode = [ "n" ];
      action.__raw = ''
        function()
          local line = vim.fn.line(".")
          vim.cmd "silent! keeppatterns %s/\\s\\+$//e"
          vim.cmd("silent! keepjumps normal! " .. line .. "G")
        end
      '';
    }
  ];

  # Learn more at https://neovim.io/doc/user/ft_sql.html#sql-completion-customization
  programs.nixvim.extraFiles."ftdetect/sql.lua".text = # lua
    ''
      vim.g.omni_sql_no_default_maps = 1
    '';

  programs.nixvim.autoCmd = [
    # Open help windows on the right in a vertical split, credits @EvanPurkhiser.
    {
      event = [ "FileType" ];
      pattern = "help";
      callback.__raw = ''
        function()
          vim.cmd "wincmd L"
          vim.cmd "vertical resize 78"
          vim.keymap.set("n", "q", ":bwipeout<CR>", { buffer = true, silent = true })
        end
      '';
    }
    {
      event = [ "FileType" ];
      pattern = "qf";
      callback.__raw = ''
        function()
          vim.api.nvim_buf_set_option(0, "modifiable", true) -- Make the quickfix buffer modifiable.

          vim.keymap.set("n", "q", ":cclose<CR>:lclose<CR>", { buffer = true, silent = true, desc = "Close quickfix/location list" })
          vim.keymap.set("n", "<C-T>", "^<C-W>gF", { buffer = true, desc = "Open in new tab (Ctrl-T)" })
          vim.keymap.set("n", "t", "^<C-W>gF", { buffer = true, desc = "Open in new tab (t)" })

          local function open_unique_qf_files()
            local qf_list = vim.fn.getqflist()
            if not qf_list or #qf_list == 0 then
              vim.notify("Quickfix list is empty.", vim.log.levels.INFO)
              return
            end

            local unique_files_info = {}
            local seen_files = {}

            for _, item in ipairs(qf_list) do
              if item.valid == 1 and item.bufnr ~= 0 then
                local filename = vim.fn.bufname(item.bufnr)
                -- Ensure filename is not empty (can happen for non-file buffers)
                if filename and filename ~= "" then
                  local abs_filename = vim.fn.fnamemodify(filename, ":p") -- Get absolute path
                  if not seen_files[abs_filename] then
                    table.insert(unique_files_info, { filename = abs_filename, lnum = item.lnum })
                    seen_files[abs_filename] = true
                  end
                end
              end
            end

            if #unique_files_info == 0 then
              vim.notify("No valid files found in quickfix list to open.", vim.log.levels.INFO)
              return
            end

            for _, file_info in ipairs(unique_files_info) do
              local escaped_filename = vim.fn.fnameescape(file_info.filename)
              vim.cmd("tabedit +" .. file_info.lnum .. " " .. escaped_filename)
            end
          end

          vim.keymap.set("n", "<C-A>", open_unique_qf_files, { buffer = true, silent = true, desc = "Open unique quickfix files in tabs" })
        end
      '';
    }
  ];
}
