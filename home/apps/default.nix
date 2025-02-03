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

  # The home.packages option allows you to install Nix packages into your environment.
  home.packages = with pkgs; [
    dconf2nix
    mise
    trash-cli
    wl-clipboard

    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')
  ];
}
