{ pkgs-unstable, ... }:
{
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;

    mise = {
      enable = true;
      package = pkgs-unstable.mise;
    };
  };
}
