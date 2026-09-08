{
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:
let
  bruno = pkgs.callPackage ./bruno/package.nix { };
  clipboard2markdown = pkgs.callPackage ./clipboard2markdown/package.nix {
    inherit (pkgs) pandoc;
  };
  nsx = pkgs.callPackage ./nsx/package.nix { };
  slack = pkgs.callPackage ./slack/package.nix { };
  viber = pkgs.callPackage ./viber/package.nix { };
in
{
  imports = [
    # CLI
    ./ast-grep
    ./claude-code
    ./codex
    ./difft-unified
    ./direnv
    ./eza
    ./fzf
    ./ghostty
    ./git
    ./git-lines
    ./slopsift
    ./httpie
    ./jq
    ./less
    ./mcporter
    ./mise
    ./nh
    ./nixvim
    ./nodejs
    ./ov
    ./python
    ./ripgrep
    ./tig
    ./tmux
    ./unicode-tussle
    ./voxize
    ./zoxide
    ./zsh

    # AI era tools
    ./gh

    # GUI
    ./brave
    ./dropbox
    ./eog
    ./firefox
    ./mpv
    ./swappy
    ./thunderbird
    ./typora
    ./vscode
  ];

  home.packages = with pkgs; [
    # Essentials
    bc
    dig
    file
    gcc14
    gnumake
    inetutils
    inotify-tools
    killall
    moreutils
    unzip
    usbutils
    wget
    zip

    # CLI
    android-tools
    bun
    clipboard2markdown
    dconf2nix
    deno
    envchain
    ffmpeg
    (lib.hiPrio file-rename)
    fx
    ghostscript
    imagemagick
    libsecret
    lsof
    nsx
    ocrmypdf
    qemu
    rclone
    scrcpy
    tesseract
    trash-cli
    tree
    try
    unp
    wineWow64Packages.stable
    wl-clipboard
    yq-go
    yt-dlp

    # AI era tools
    mcporter
    n8n-cli

    # GUI
    bottles
    bruno
    gnome-firmware
    gnome-tweaks
    google-chrome
    heidisql
    inkscape
    keepassxc
    onlyoffice-desktopeditors
    papers
    pkgs-unstable.proton-pass
    proton-vpn
    remmina
    slack
    viber
  ];
}
