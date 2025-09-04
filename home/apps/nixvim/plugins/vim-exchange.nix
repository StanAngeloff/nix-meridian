{ pkgs, ... }:
{
  programs.nixvim = {
    extraPlugins = with pkgs.vimPlugins; [
      vim-exchange
    ];

    globals = {
      exchange_no_mappings = 1;
    };

    keymaps = [
      # nixfmt: off
      { key = "X"; mode = [ "x" ]; action = "<Plug>(Exchange)"; }
      # nixfmt: on
    ];
  };
}
