{ pkgs-unstable, ... }:
{
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;

    # Learn more at https://github.com/nix-community/nix-direnv
    nix-direnv.enable = true;

    mise = {
      enable = true;
      package = pkgs-unstable.mise;
    };
  };
}
