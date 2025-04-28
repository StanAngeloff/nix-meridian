{ pkgs-unstable, ... }:
{
  programs.nixvim.plugins.nvim-autopairs = {
    enable = true;
    package = pkgs-unstable.vimPlugins.nvim-autopairs;

    settings = {
      check_ts = true;
    };
  };
}
