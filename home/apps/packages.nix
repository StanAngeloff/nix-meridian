{ pkgs, pkgs-unstable, ... }:
let
  clipboard2markdown = pkgs.callPackage ./clipboard2markdown { };
  viber = pkgs.callPackage ./viber { };
in
{
  # List packages installed in your user profile. To search, run:
  # $ nix search wget
  packages = with pkgs; [
    # Essentials
    deno
    gcc14
    gnumake
    inetutils
    moreutils
    python312
    usbutils

    # CLI
    clipboard2markdown
    dconf2nix
    dig
    envchain
    ffmpeg
    imagemagick
    inotify-tools
    killall
    libsecret
    python312Packages.ocrmypdf
    qemu
    rclone
    scrcpy
    tesseract
    trash-cli
    tree
    unp
    unzip
    wget
    wineWowPackages.stable
    wl-clipboard
    yt-dlp

    # GUI
    apostrophe
    bottles
    gnome-firmware
    gnome-tweaks
    google-chrome
    inkscape
    onlyoffice-desktopeditors
    pkgs-unstable.proton-pass
    protonvpn-gui
    slack
    viber
  ];
}
