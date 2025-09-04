{ pkgs-unstable, ... }:
{
  programs.nixvim = {
    plugins.yanky = {
      enable = true;
      package = pkgs-unstable.vimPlugins.yanky-nvim;

      settings = {
        highlight = {
          on_yank = false;
          on_put = false;
        };

        system_clipboard = {
          clipboard_register = "+";
          sync_with_ring = true;
        };
      };
    };

    keymaps = [
      # nixfmt: off
      { key = "y"; mode = [ "n" "x" ]; action = "<Plug>(YankyYank)"; }

      { key = "p"; mode = [ "n" "x" ]; action = "<Plug>(YankyPutAfter)"; }
      { key = "P"; mode = [ "n" "x" ]; action = "<Plug>(YankyPutBefore)"; }
      { key = "gp"; mode = [ "n" "x" ]; action = "<Plug>(YankyGPutAfter)"; }
      { key = "gP"; mode = [ "n" "x" ]; action = "<Plug>(YankyGPutBefore)"; }

      { key = "<c-p>"; mode = [ "n" ]; action = "<Plug>(YankyPreviousEntry)"; options.desc = "Select previous entry through yank history"; }
      { key = "<c-n>"; mode = [ "n" ]; action = "<Plug>(YankyNextEntry)"; options.desc = "Select next entry through yank history"; }
      # nixfmt: on
    ];
  };
}
