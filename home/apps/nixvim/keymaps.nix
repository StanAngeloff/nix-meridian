{
  programs.nixvim.globals.mapleader = ",";

  programs.nixvim.keymaps = [
    { key = "j"; mode = [ "n" ]; action = "gj"; options.silent = true; }
    { key = "k"; mode = [ "n" ]; action = "gk"; options.silent = true; }
    { key = "j"; mode = [ "v" ]; action = "gj"; options.silent = true; }
    { key = "k"; mode = [ "v" ]; action = "gk"; options.silent = true; }
    # Make Y consistent with C and D. See ':help Y'.
    { key = "Y"; mode = [ "n" ]; action = "y$"; }
    # Make $ behave consistently in visual mode.
    { key = "$"; mode = [ "v" ]; action = "g_"; }
    # NERDTree project navigation.
    { key = "<Tab>"; mode = "n"; action.__raw = ''function() vim.cmd.NERDTreeMirrorToggle() end''; }
    # Q for 'Q'uit, 'Ex' mode has received zero use.
    { key = "Q"; mode = [ "n" ]; action = ":windo normal ZZ<CR>"; options.silent = true; }
    { key = "Q"; mode = [ "v" ]; action = "<Esc>:windo normal ZZ<CR>"; options.silent = true; }
    # Frantic <C-S> are now hectic <Return>s
    { key = "<Return>"; mode = [ "n" ]; action = ":w<CR>"; }
    { key = "<Return>"; mode = [ "v" ]; action = ":<C-U>w<CR>gv"; }
    # Turn off active highlighting, reset signs and plug-ins.
    { key = "<leader><Space>"; mode = [ "n" ]; action = ":noh<CR>:sign unplace *<CR>:call clearmatches()<CR>:GitGutter<CR>"; options.silent = true; }
    # Toggle spell-checking, paste-mode, long line wrap, and placeholder characters.
    { key = "<F1>"; mode = [ "n" ]; action = ":setlocal nospell! nospell?<CR>"; options.silent = true; }
    { key = "<F2>"; mode = [ "n" ]; action = ":setlocal invpaste paste?<CR>"; options.silent = true; }
    { key = "<F3>"; mode = [ "n" ]; action = ":setlocal wrap! wrap?<CR>"; options.silent = true; }
    { key = "<F4>"; mode = [ "n" ]; action = ":setlocal list! list?<CR>"; options.silent = true; }
    # Show the stack of syntax highlighting classes affecting whatever is under the cursor.
    { key = "<F7>"; mode = [ "n" ]; action = ":TSHighlightCapturesUnderCursor<CR>"; options.silent = true; }
    # Quick tab creation and navigation.
    { key = "<leader>tn"; mode = [ "n" ]; action = ":tabnew<CR>"; }
    { key = "<leader>tm"; mode = [ "n" ]; action = ":tabmove"; }
    { key = "<leader>te"; mode = [ "n" ]; action = "':tabedit '"; options.expr = true; }
    # Copy to & paste from the system clipboard.
    { key = "<leader>p"; mode = [ "n" ]; action = "\"+p"; }
    { key = "<leader>P"; mode = [ "n" ]; action = "\"+P"; }
    { key = "<leader>p"; mode = [ "v" ]; action = "\"+p"; }
    { key = "<leader>P"; mode = [ "v" ]; action = "\"+P"; }
    { key = "<leader>y"; mode = [ "v" ]; action = "\"+y"; }
    { key = "<leader>d"; mode = [ "v" ]; action = "\"+d"; }
    # " Copy entire buffer to X clipboard.
    { key = "<leader>="; mode = [ "n" ]; action = "mZggVG\"+yg`Z"; }
    # Tab navigation
    { key = "<C-J>"; mode = [ "n" ]; action = "gt"; options.silent = true; }
    { key = "<C-K>"; mode = [ "n" ]; action = "gT"; options.silent = true; }
    # Adjust the tab/shift width keyboard bindings.
    { key = "<leader>w2"; mode = [ "n" ]; action = ":setlocal tabstop=2<CR>:setlocal shiftwidth=2<CR>"; }
    { key = "<leader>w4"; mode = [ "n" ]; action = ":setlocal tabstop=4<CR>:setlocal shiftwidth=4<CR>"; }
    { key = "<leader>w8"; mode = [ "n" ]; action = ":setlocal tabstop=8<CR>:setlocal shiftwidth=8<CR>"; }
    { key = "<leader>w<Tab>"; mode = [ "n" ]; action = ":setlocal noexpandtab<CR>:retab<CR>:echo 'expandtab'<CR>"; options.silent = true; }
    { key = "<leader>w<Space>"; mode = [ "n" ]; action = ":setlocal expandtab<CR>:retab<CR>:echo 'noexpandtab'<CR>"; options.silent = true; }
    # Restore last implicit selection (e.g., on paste) in VISUAL mode.
    { key = "<leader>v"; mode = [ "n" ]; action = "g`[Vg`]o"; }
    # Escape, escape!
    { key = "<C-C>"; mode = [ "n" "i" "v" ]; action = "<Esc><Esc>"; }
    # Start a new Undo group before making changes in INSERT mode.
    { key = "<C-W>"; mode = [ "i" ]; action = "<C-G>u<C-W>"; }
    { key = "<C-R>"; mode = [ "i" ]; action = "<C-G>u<C-R>"; }
    # Sorting like a pro!
    { key = "<leader>sip"; mode = [ "n" ]; action = "mZvip:sort u<CR>g`Z:echo (line(\"'>\") - line(\"'<\") + 1) . ' line(s) sorted'<CR>"; options.silent = true; }
    { key = "<leader>si{"; mode = [ "n" ]; action = "mZvi{:sort u<CR>g`Z:echo (line(\"'>\") - line(\"'<\") + 1) . ' line(s) sorted'<CR>"; options.silent = true; }
    { key = "<leader>si["; mode = [ "n" ]; action = "mZvi[:sort u<CR>g`Z:echo (line(\"'>\") - line(\"'<\") + 1) . ' line(s) sorted'<CR>"; options.silent = true; }
    { key = "<leader>s"; mode = [ "v" ]; action = ":sort u<CR>gv"; options.silent = true; }
    # Searching like a pro!
    { key = "<leader>S"; mode = [ "n" "v" ]; action.__raw = ''function() vim.cmd.FzfLua("grep_project") end''; }
    # Jump to the first non-whitespace character on the line or the beginning of the line.
    { key = "0"; mode = [ "n" "v" ]; options.expr = true; action.__raw = ''
      function()
        local line = vim.fn.getline(".")
        local col = vim.fn.col(".")
        local before = line:sub(1, col)
        if before:match("^%s+%S$") then
          return "0"
        end
        return "^"
      end
    ''; }
    # Strip trailing whitespace.
    { key = "<leader>W"; mode = [ "n" ]; action.__raw = ''
      function()
        vim.cmd "silent! keeppatterns %s/\\s\\+$//e"
      end
    ''; }
  ];
}
