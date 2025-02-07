{ pkgs, ... }:
{
  imports = [
    ./alacritty
    ./direnv
    ./dropbox
    ./eza
    ./firefox
    ./fzf
    ./git
    ./jump
    ./keepassxc
    ./less
    ./mise
    ./nixvim
    ./proton
    ./ripgrep
    ./thunderbird
    ./tig
    ./tmux
    ./unicode-tussle
    ./vscode
    ./zsh
  ];

  # List packages installed in your user profile. To search, run:
  # $ nix search wget
  home.packages = with pkgs; [
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

    (viber.overrideAttrs (
      finalAttrs: previousAttrs: {
        installPhase = ''
          ${previousAttrs.installPhase or ""}

          substituteInPlace $out/share/applications/viber.desktop \
            --replace Path=/opt/viber/ Path=$out/opt/viber/
        '';
      }
    ))
  ];
}
