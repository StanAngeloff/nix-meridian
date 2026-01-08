{ pkgs, ... }:
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

    plugins = with pkgs.tmuxPlugins; [
      {
        plugin = fuzzback;
        extraConfig = # tmux
          ''
            set -g @fuzzback-bind /
          '';
      }
    ];

    extraConfig = ''
      ${builtins.readFile ./tmux.conf}
      ${builtins.readFile ./abilities/tmux.tig.conf}
      ${builtins.readFile ./abilities/tmux.nix-diff.conf}
    '';
  };
}
