{
  imports = [
    ./aliases.nix
  ];

  programs.zsh = {
    enable = true;
    enableCompletion = true;

    initExtra = ''
      [[ -f "$HOME/.zshenv" ]] && . "$HOME/.zshenv"

      eval "$(mise activate zsh)"
    '';

    oh-my-zsh = {
      enable = true;
      plugins = [
        "fancy-ctrl-z"
        "git-prompt"
      ];
    };
  };
}
