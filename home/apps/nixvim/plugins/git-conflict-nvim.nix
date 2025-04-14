{ pkgs-unstable, ... }:
{
  programs.nixvim.plugins.git-conflict = {
    enable = true;
    package = pkgs-unstable.vimPlugins.git-conflict-nvim;
  };
}
