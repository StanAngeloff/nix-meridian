{
  hiPrio,
  pkgs,
  pkgs-unstable,
  ...
}:
let
  clipboard2markdown = pkgs.callPackage ./clipboard2markdown {
    pandoc = pkgs-unstable.pandoc;
  };
  viber = pkgs.callPackage ./viber { };
in
{
  # List packages installed in your user profile. To search, run:
  # $ nix search wget
  packages = with pkgs; [
    # Essentials
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
    clipboard2markdown
    dconf2nix
    deno
    ffmpeg
    ghostscript
    imagemagick
    libsecret
    python312
    python312Packages.ocrmypdf
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
    (hiPrio file-rename)

    # GUI
    eog
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
