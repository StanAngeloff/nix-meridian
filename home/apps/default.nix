{ pkgs, ... }:
let
  packages = import ./packages.nix { inherit pkgs; };
in
{
  imports = [
    ./alacritty
    ./direnv
    ./dropbox
    ./eza
    ./firefox
    ./fzf
    ./git
    ./jq
    ./jump
    ./keepassxc
    ./less
    ./mise
    ./nixvim
    ./proton
    ./ripgrep
    ./thunderbird
    ./tig
    ./tmux
    ./unicode-tussle
    ./vscode
    ./zsh
  ];

  home.packages = packages.packages;
}
