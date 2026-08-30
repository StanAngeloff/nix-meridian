{ pkgs, osConfig, ... }:
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

  nameWindow = pkgs.writeShellScript "tmux-name-window" ''
    adjectives=(
      big old shy mad sad red hot cold cool calm
      bold dim dry fat fit flat glad grim keen kind
      lazy lean loud mean mild neat odd pale pink plum
      posh raw rich ripe rude slim slow smug soft sour
      tall tame thin tiny warm weak wide wild wise dull
    )
    animals=(
      ant ape bat bear bee boar bull cat cod cow
      crab crow deer dog dove duck eel elk ewe fish
      fly fox frog goat gull hare hawk hen hog jay
      koi lamb lark lion lynx mare mink mole moth mule
      newt owl ox pig pug ram rat seal slug swan
      toad vole wasp wolf worm wren yak
    )
    existing=$(${tmux} list-windows -F '#{window_name}' 2>/dev/null)
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      name="$(shuf -n1 -e "''${adjectives[@]}")-$(shuf -n1 -e "''${animals[@]}")"
      echo "$existing" | grep -qxF "$name" || break
    done
    echo "$name"
  '';

  popupNvim = import ../../../modules/lib/popup-nvim.nix { inherit pkgs; };

  scratchNote = pkgs.writeShellScript "tmux-scratch-note" ''
    pane_id="$1"
    pane_pid="$2"
    notes_path="$HOME/.cache/tmux-scratch-notes"
    mkdir -p "$notes_path"
    note="$notes_path/$pane_id-$pane_pid.md"
    ${popupNvim}/bin/popup-nvim "$note"
    if [ -f "$note" ] && ! grep -q '[^[:space:]]' "$note"; then
      rm -f "$note"
    fi
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

    plugins = [ ];

    extraConfig = ''
      ${builtins.readFile ./claude-state.conf}
      ${
        let
          replacements = {
            "@dismissClaudeIdle@" = "${dismissClaudeIdle}";
            "@machineName@" = osConfig.networking.hostName;
            "@nameWindow@" = "${nameWindow}";
          };
        in
        builtins.replaceStrings (builtins.attrNames replacements) (builtins.attrValues replacements) (
          builtins.readFile ./tmux.conf
        )
      }
      ${builtins.readFile ./abilities/tmux.tig.conf}
      ${builtins.readFile ./abilities/tmux.nix-diff.conf}
      ${builtins.replaceStrings [ "@scratchNote@" ] [ "${scratchNote}" ] (
        builtins.readFile ./abilities/tmux.scratch-note.conf
      )}
    '';
  };
}
