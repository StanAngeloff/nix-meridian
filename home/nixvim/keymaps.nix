{
  programs.nixvim.globals.mapleader = ",";

  programs.nixvim.keymaps = [
    {
      action.__raw = ''function() vim.cmd.NERDTreeMirrorToggle() end'';
      key = "<Tab>";
      mode = "n";
    }
    {
      key = "Q";
      mode = [ "n" "v" ];
      options.silent = true;
      action.__raw = ''
        function()
          local mode = vim.api.nvim_get_mode().mode
          if mode == "v" or mode == "V" then
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
            vim.schedule(function()
              vim.cmd("windo normal ZZ")
            end)
          else
            vim.cmd("windo normal ZZ")
          end
        end
      '';
    }
  ];
}
