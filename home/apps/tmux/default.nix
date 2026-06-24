{ pkgs, ... }:
let
  tmux = "${pkgs.tmux}/bin/tmux";

  # Debounced clear of the Claude Code "idle" (green) status dot.
  #
  # The after-select-window hook launches this in the background with the just-selected window ID as $1.
  # After a short dwell it clears the dot only if that window is STILL focused and STILL idle,
  # so cycling past a window with Ctrl+Tab leaves before the dwell elapses and nothing is wiped.
  dismissClaudeIdle = pkgs.writeShellScript "tmux-dismiss-claude-idle" ''
    expected="$1"
    sleep 2
    [ "$(${tmux} display-message -p -t "$expected" '#{window_active}')" = 1 ] || exit 0
    [ "$(${tmux} show-options -wqv -t "$expected" @claude-state)" = idle ] || exit 0
    ${tmux} set-option -wu -t "$expected" @claude-state
    ${tmux} refresh-client -S 2>/dev/null || true
  '';
in
{
  programs.tmux = {
    enable = true;

    sensibleOnTop = true;

    aggressiveResize = true;
    baseIndex = 1;
    clock24 = true;
    escapeTime = 0;
    focusEvents = true;
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
      ${builtins.replaceStrings [ "@dismissClaudeIdle@" ] [ "${dismissClaudeIdle}" ] (
        builtins.readFile ./tmux.conf
      )}
      ${builtins.readFile ./abilities/tmux.tig.conf}
      ${builtins.readFile ./abilities/tmux.nix-diff.conf}
    '';
  };
}
