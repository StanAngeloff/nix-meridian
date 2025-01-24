{ pkgs, ... }:
{
  imports = [
    ./fzf
    ./git
    ./gnome-shell
    ./nixvim
    ./ssh
    ./zsh
  ];

  home.packages = with pkgs; [
    dconf2nix
    mise
  ];
}
