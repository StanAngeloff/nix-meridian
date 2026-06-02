{
  config,
  lib,
  pkgs,
  ...
}:
let
  tmux-claude-state =
    let
      tmux = "${lib.getBin pkgs.tmux}/bin/tmux";
    in
    {
      set =
        state: "[ -n \"$TMUX_PANE\" ] && ${tmux} set -w -t \"$TMUX_PANE\" @claude-state ${state} || true";
      reset = "[ -n \"$TMUX_PANE\" ] && ${tmux} set -wu -t \"$TMUX_PANE\" @claude-state || true";
      reset-blocked = "[ -n \"$TMUX_PANE\" ] && case \"$(${tmux} show -wv -t \"$TMUX_PANE\" @claude-state 2>/dev/null)\" in permission|elicitation) ${tmux} set -wu -t \"$TMUX_PANE\" @claude-state;; esac; true";
    };

  hooks = {
    PermissionRequest = [
      {
        hooks = [
          {
            type = "command";
            command = "${lib.getBin pkgs.pipewire}/bin/pw-play ${./audio/notifications/mixkit-clear-announce-tones-2861.mp3}";
            timeout = 5;
          }
          {
            type = "command";
            command = tmux-claude-state.set "permission";
            timeout = 2;
          }
        ];
      }
    ];
    Elicitation = [
      {
        hooks = [
          {
            type = "command";
            command = tmux-claude-state.set "elicitation";
            timeout = 2;
          }
        ];
      }
    ];
    Stop = [
      {
        hooks = [
          {
            type = "command";
            command = tmux-claude-state.set "idle";
            timeout = 2;
          }
        ];
      }
    ];
    StopFailure = [
      {
        hooks = [
          {
            type = "command";
            command = tmux-claude-state.set "idle";
            timeout = 2;
          }
        ];
      }
    ];
    PostToolUse = [
      {
        hooks = [
          {
            type = "command";
            command = tmux-claude-state.reset-blocked;
            timeout = 2;
          }
        ];
      }
    ];
    UserPromptSubmit = [
      {
        hooks = [
          {
            type = "command";
            command = tmux-claude-state.reset;
            timeout = 2;
          }
        ];
      }
    ];
    SessionEnd = [
      {
        hooks = [
          {
            type = "command";
            command = tmux-claude-state.reset;
            timeout = 2;
          }
        ];
      }
    ];
  };
in
{
  home.activation.updateClaudeCodeNotifications =
    let
      jq = lib.getExe pkgs.jq;
      sponge = "${lib.getBin pkgs.moreutils}/bin/sponge";
    in
    lib.hm.dag.entryAfter [ "updateClaudeCodeSettings" ] ''
      settingsFile="${config.home.homeDirectory}/.claude/settings.json"

      ${jq} ${lib.strings.escapeShellArg ".hooks = ${builtins.toJSON hooks}"} "$settingsFile" | ${sponge} "$settingsFile"
    '';
}
