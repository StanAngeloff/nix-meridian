{ pkgs, ... }:
{
  imports = [
    ./alacritty
    ./direnv
    ./eza
    ./firefox
    ./fzf
    ./git
    ./jump
    ./keepassxc
    ./less
    ./mise
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
    trash-cli
    wl-clipboard

    # GUI
    emote
    gnome-tweaks
    google-chrome
    slack
  ];
}
