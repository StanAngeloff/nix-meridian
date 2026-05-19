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
    ./direnv
    ./eza
    ./fzf
    ./ghostty
    ./git
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

    # GUI
    ./brave
    ./dropbox
    ./eog
    ./firefox
    ./swappy
    ./thunderbird
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

    # CLI
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
    pkgs-unstable.ocrmypdf
    qemu
    rclone
    scrcpy
    tesseract
    trash-cli
    tree
    unp
    wineWowPackages.stable
    wl-clipboard
    yt-dlp

    # AI era tools
    gh
    mcporter
    n8n-cli

    # GUI
    apostrophe
    bottles
    bruno
    gnome-firmware
    gnome-tweaks
    google-chrome
    inkscape
    keepassxc
    onlyoffice-desktopeditors
    papers
    pkgs-unstable.proton-pass
    protonvpn-gui
    remmina
    slack
    viber
  ];
}
