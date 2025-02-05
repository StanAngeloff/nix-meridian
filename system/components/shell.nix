{ pkgs, ... }:
{
  # Make Zsh the default on a system level.
  programs.zsh = {
    enable = true;
  };
  users.defaultUserShell = pkgs.zsh;
  environment.shells = [ pkgs.zsh ];
}
