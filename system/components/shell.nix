{ lib, pkgs, ... }:
{
  # Make Zsh the default on a system level.
  programs.zsh = {
    enable = true;
  };
  users.defaultUserShell = pkgs.zsh;
  environment.shells = [ pkgs.zsh ];

  # Override the default EDITOR="nano" from nixos/modules/programs/environment.nix.
  environment.variables.EDITOR = lib.mkForce null;
}
