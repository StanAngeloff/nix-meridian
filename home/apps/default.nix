{ pkgs, ... }:
{
  imports = [
    ./alacritty
    ./eza
    ./firefox
    ./fzf
    ./git
    ./jump
    ./less
    ./nixvim
    ./ripgrep
    ./thunderbird
    ./tig
    ./tmux
    ./vscode
    ./zsh
  ];

  # List packages installed in your user profile. To search, run:
  # $ nix search wget
  home.packages = with pkgs; [
    # Essentials
    gcc14
    gnumake
    nodejs_22
    python313

    # CLI
    dconf2nix
    mise
    trash-cli
    wl-clipboard

    # GUI
    emote
    gnome-tweaks
    google-chrome
    slack
  ];
}
