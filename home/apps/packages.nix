{
  hiPrio,
  pkgs,
  pkgs-unstable,
  ...
}:
let
  bruno = pkgs.callPackage ./bruno/package.nix { };
  clipboard2markdown = pkgs.callPackage ./clipboard2markdown/package.nix {
    pandoc = pkgs-unstable.pandoc;
  };
  nsx = pkgs.callPackage ./nsx/package.nix { };
  viber = pkgs.callPackage ./viber/package.nix { };
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
    pkgs-unstable.deno
    ffmpeg
    ghostscript
    imagemagick
    libsecret
    nsx
    python313
    #python313Packages.ocrmypdf
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
    apostrophe
    bottles
    bruno
    eog
    gnome-firmware
    gnome-tweaks
    google-chrome
    inkscape
    onlyoffice-desktopeditors
    papers
    pkgs-unstable.proton-pass
    protonvpn-gui
    slack
    viber
  ];
}
