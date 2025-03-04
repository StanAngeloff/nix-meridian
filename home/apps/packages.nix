{ pkgs, ... }:
let
  clipboard2markdown = import ./clipboard2markdown { inherit pkgs; };
  proton-pass = import ./proton-pass { inherit pkgs; };
  viber = import ./viber { inherit pkgs; };
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
    clipboard2markdown.package
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
    wget
    wineWowPackages.stable
    wl-clipboard
    yt-dlp

    # GUI
    bottles
    gnome-firmware
    gnome-tweaks
    google-chrome
    inkscape
    onlyoffice-desktopeditors
    proton-pass.package
    protonvpn-gui
    slack
    viber.package
  ];
}
