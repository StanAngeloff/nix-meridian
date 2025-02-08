{ pkgs, ... }:
let
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
    dconf2nix
    envchain
    httpie
    imagemagick
    trash-cli
    wl-clipboard
    yt-dlp

    # GUI
    emote
    gnome-tweaks
    google-chrome
    slack
    viber.package
  ];
}
