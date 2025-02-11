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
    nodejs_22
    pnpm_10
    python313

    # CLI
    clipboard2markdown.package
    dconf2nix
    envchain
    httpie
    imagemagick
    rclone
    scrcpy
    trash-cli
    wl-clipboard
    yt-dlp

    # GUI
    emote
    gnome-tweaks
    google-chrome
    onlyoffice-desktopeditors
    proton-pass.package
    protonvpn-gui
    slack
    viber.package
  ];
}
