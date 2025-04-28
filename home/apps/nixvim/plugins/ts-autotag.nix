{ pkgs-unstable, ... }:
{
  programs.nixvim.plugins.ts-autotag = {
    enable = true;
    package = pkgs-unstable.vimPlugins.nvim-ts-autotag;
  };
}
