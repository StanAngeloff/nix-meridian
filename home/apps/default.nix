{ pkgs, pkgs-unstable, ... }:
let
  packages = import ./packages.nix { inherit pkgs pkgs-unstable; };
in
{
  imports = [
    ./alacritty
    ./brave
    ./direnv
    ./dropbox
    ./eza
    ./firefox
    ./fzf
    ./git
    ./httpie
    ./jq
    ./jump
    ./keepassxc
    ./less
    ./mise
    ./nixvim
    ./nodejs+pnpm
    ./ripgrep
    ./swappy
    ./thunderbird
    ./tig
    ./tmux
    ./unicode-tussle
    ./vscode
    ./zsh
  ];

  home.packages = packages.packages;
}
