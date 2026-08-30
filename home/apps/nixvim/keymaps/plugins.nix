{
  programs.nixvim.keymaps = [
    # nixfmt: off
    { key = "<leader><Space>"; mode = [ "n" ]; action = ":noh<CR>:sign unplace *<CR>:call clearmatches()<CR>:Gitsigns refresh<CR>"; options.silent = true; options.desc = "Turn off active highlighting, reset signs and plug-ins"; }
    { key = "<F6>"; mode = [ "n" ]; action.__raw = "function() vim.cmd.UndotreeToggle() end"; }
    { key = "<F7>"; mode = [ "n" ]; action = ":TSHighlightCapturesUnderCursor<CR>"; options.silent = true; options.desc = "Show the stack of syntax highlighting classes affecting whatever is under the cursor"; }
    { key = "<leader>sip"; mode = [ "n" ]; action = "mZvip:Sort<CR>g`Z:echo (line(\"'>\") - line(\"'<\") + 1) . ' line(s) sorted'<CR>"; options.silent = true; }
    { key = "<leader>si{"; mode = [ "n" ]; action = "mZvi{:Sort<CR>g`Z:echo (line(\"'>\") - line(\"'<\") + 1) . ' line(s) sorted'<CR>"; options.silent = true; }
    { key = "<leader>si["; mode = [ "n" ]; action = "mZvi[:Sort<CR>g`Z:echo (line(\"'>\") - line(\"'<\") + 1) . ' line(s) sorted'<CR>"; options.silent = true; }
    { key = "<leader>s"; mode = [ "v" ]; action = ":sort u<CR>gv"; options.silent = true; }
    { key = "<leader>0"; mode = [ "n" ]; action.__raw = ''function() require("fzf-lua").git_files({ query = vim.fn.expand("<cword>"), cmd = "git ls-files --cached --others --exclude-standard" }) end''; }
    { key = "<leader>S"; mode = [ "n" ]; action.__raw = ''function() require("fzf-lua").live_grep({ search = "" }) end''; }
    { key = "<leader>S"; mode = [ "v" ]; action.__raw = ''function() require("fzf-lua").live_grep({ search = require("fzf-lua.utils").get_visual_selection() }) end''; }
    { key = "<leader>ha"; mode = [ "n" ]; action.__raw = ''function() vim.cmd.Git("add %") end''; }
    { key = "<leader>hp"; mode = [ "n" ]; action = ":Gitsigns preview_hunk<CR>"; options.silent = true; }
    { key = "<leader>hs"; mode = [ "n" "v" ]; action = ":Gitsigns stage_hunk<CR>"; options.silent = true; }
    { key = "<leader>hu"; mode = [ "n" ]; action = ":Gitsigns reset_hunk<CR>"; options.silent = true; }
    { key = "[c"; mode = [ "n" ]; action = ":Gitsigns nav_hunk prev<CR>"; options.silent = true; }
    { key = "]c"; mode = [ "n" ]; action = ":Gitsigns nav_hunk next<CR>"; options.silent = true; }
    { key = "ih"; mode = [ "o" ]; action = "<Cmd>Gitsigns select_hunk<CR>"; }
    { key = "ih"; mode = [ "x" ]; action = "<Cmd>Gitsigns select_hunk<CR>"; }
    { key = "[b"; mode = [ "v" ]; action = ":<C-U>call base64#v_atob()<CR>"; options.silent = true; }
    { key = "]b"; mode = [ "v" ]; action = ":<C-U>call base64#v_btoa()<CR>"; options.silent = true; }
    # nixfmt: on
  ];

  programs.nixvim.autoCmd = [
    {
      event = [ "FileType" ];
      pattern = "markdown,chat";
      callback.__raw = ''
        function()
          vim.keymap.set("n", "<leader>m", ":MarkdownPreview<CR>", { buffer = true, silent = true, desc = "Open Markdown preview" })
        end
      '';
    }
  ];
}
