{
  programs.tmux = {
    enable = true;

    sensibleOnTop = true;

    aggressiveResize = true;
    baseIndex = 1;
    clock24 = true;
    escapeTime = 0;
    historyLimit = 102400;
    keyMode = "vi";
    mouse = true;
    prefix = "C-s";
    terminal = "tmux-256color";

    extraConfig = ''
      ${builtins.readFile ./tmux.conf}
      ${builtins.readFile ./tmux.tig.conf}
    '';
  };
}
