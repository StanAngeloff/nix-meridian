{ pkgs, ... }:
let
  tmux = "${pkgs.tmux}/bin/tmux";

  # Debounced dim of the Claude Code idle status dot: bright green (unread) fades to dim green (read).
  #
  # The after-select-window hook launches this in the background with the just-selected window ID as $1.
  # After a short dwell it clears @claude-unread on that window's panes, but only if the window is STILL focused, so cycling past a window with Ctrl+Tab (which leaves before the dwell elapses) keeps the bright dot.
  dismissClaudeIdle = pkgs.writeShellScript "tmux-dismiss-claude-idle" ''
    expected="$1"
    sleep 2
    [ "$(${tmux} display-message -p -t "$expected" '#{window_active}')" = 1 ] || exit 0
    ${tmux} list-panes -t "$expected" -F '#{pane_id}' | while read -r pane_id; do
      ${tmux} set -pu -t "$pane_id" @claude-unread 2>/dev/null || true
    done
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
      ${builtins.readFile ./claude-state.conf}
      ${builtins.replaceStrings [ "@dismissClaudeIdle@" ] [ "${dismissClaudeIdle}" ] (
        builtins.readFile ./tmux.conf
      )}
      ${builtins.readFile ./abilities/tmux.tig.conf}
      ${builtins.readFile ./abilities/tmux.nix-diff.conf}
    '';
  };
}
