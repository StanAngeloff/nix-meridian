{ pkgs, ... }:
{
  programs.nixvim = {
    extraPlugins = with pkgs.vimPlugins; [
      vim-exchange
    ];

    globals = {
      exchange_no_mappings = 1;
    };
  };
}
