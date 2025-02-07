{
  imports = [
    ./aliases.nix
  ];

  programs.zsh = {
    enable = true;
    enableCompletion = true;

    history = {
      append = true;
      extended = true;
      ignoreDups = true;
      ignoreSpace = true;
      save = 50000;
      size = 50000;
    };

    initExtra = ''
      setopt hist_find_no_dups
      setopt hist_no_functions
      setopt hist_no_store
      setopt hist_reduce_blanks
      setopt hist_save_no_dups
      setopt inc_append_history
      setopt no_hist_beep
    '';

    oh-my-zsh = {
      enable = true;
      theme = "macovsky";
      plugins = [
        "docker"
        "fancy-ctrl-z"
        "git-prompt"
      ];
    };
  };
}
