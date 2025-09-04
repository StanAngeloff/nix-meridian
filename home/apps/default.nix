{
  pkgs,
  pkgs-unstable,
  voxinput-pkgs,
  ...
}:
let
  packages = pkgs.callPackage ./packages.nix {
    inherit pkgs pkgs-unstable voxinput-pkgs;
  };
in
{
  imports = [
    ./alacritty
    ./ast-grep
    ./brave
    ./direnv
    ./dropbox
    ./eza
    ./figma-agent
    ./firefox
    ./fzf
    ./git
    ./httpie
    ./jq
    ./jump
    ./less
    ./mise
    ./nixvim
    ./nodejs+pnpm
    ./ov
    ./ripgrep
    ./swappy
    ./thunderbird
    ./tig
    ./tmux
    ./unicode-tussle
    ./voxinput
    ./vscode
    ./zsh
  ];

  home.packages = packages.packages;
}
