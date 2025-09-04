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
    # CLI
    ./alacritty
    ./ast-grep
    ./direnv
    ./eza
    ./fzf
    ./git
    ./httpie
    ./jq
    ./jump
    ./less
    ./mise
    ./nh
    ./nixvim
    ./nodejs+pnpm
    ./ov
    ./ripgrep
    ./tig
    ./tmux
    ./unicode-tussle
    ./voxinput
    ./zsh

    # Services
    ./figma-agent

    # GUI
    ./brave
    ./dropbox
    ./firefox
    ./swappy
    ./thunderbird
    ./vscode
  ];

  home.packages = packages;
}
