{ lib, ... }:
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
      share = false;
      ignoreDups = true;
      ignoreSpace = true;
      save = 50000;
      size = 50000;
    };

    initContent =
      let
        zshConfig = lib.mkOrder 1200 ''
          setopt hist_find_no_dups
          setopt hist_no_functions
          setopt hist_no_store
          setopt hist_reduce_blanks
          setopt hist_save_no_dups
          setopt inc_append_history
          setopt no_hist_beep

          bindkey "^H" backward-delete-word

          source ${./prompt.zsh}
        '';
        # Set terminal cursor to block whilst running a command.
        zshCursorConfig = lib.mkOrder 1000 ''
          function _zsh_cursor_block() {
            echo -ne "\e[2 q"
          }

          function _zsh_cursor_beam() {
            echo -ne "\e[6 q"
          }

          autoload -Uz add-zsh-hook

          add-zsh-hook preexec _zsh_cursor_block
          add-zsh-hook precmd _zsh_cursor_beam
        '';
      in
      lib.mkMerge [
        zshConfig
        zshCursorConfig
      ];

    oh-my-zsh = {
      enable = true;
      plugins = [
        "fancy-ctrl-z"
      ];
    };
  };
}
