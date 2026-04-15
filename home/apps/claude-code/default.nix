{
  config,
  lib,
  pkgs,
  ...
}:
let
  claude-code = {
    package = "@anthropic-ai/claude-code";
    version = "latest";
    args = "--effort max"; # This one wins over settings.json.
    env = {
      DISABLE_AUTOUPDATER = 1;
      FORCE_AUTOUPDATE_PLUGINS = 1;
      DISABLE_INSTALLATION_CHECKS = 1;
      USE_BUILTIN_RIPGREP = 0;
      MAX_THINKING_TOKENS = 64000;
      # See "[BUG] Logo and "Thinking" animation colors are dull/washed-out inside tmux" https://github.com/anthropics/claude-code/issues/35148#issuecomment-4073207670
      TMUX = "";
      # See "[MODEL] Claude Code is unusable for complex engineering tasks with the Feb updates" https://github.com/anthropics/claude-code/issues/42796
      CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING = 1;
      CLAUDE_CODE_EFFORT_LEVEL = "max"; # This one is ignored in favor of settings.json, but I'm _hoping_ has some influence on sub-agents.
    };
    settings = {
      "$schema" = "https://json.schemastore.org/claude-code-settings.json";
      alwaysThinkingEnabled = true;
      effortLevel = "high";
      showThinkingSummaries = true;
      spinnerTipsEnabled = false;
    };
    # See "[BUG] v2.1.94 silently changed Ctrl+L default" https://github.com/anthropics/claude-code/issues/45364
    keybindings = {
      "$schema" = "https://json.schemastore.org/claude-code-keybindings.json";
      bindings = [
        {
          context = "Global";
          bindings = {
            "ctrl+l" = "app:redraw";
          };
        }
        {
          context = "Chat";
          bindings = {
            "ctrl+l" = null;
          };
        }
      ];
    };
  };

  bun = pkgs.bun;
  jq = lib.getExe pkgs.jq;
  sponge = "${lib.getBin pkgs.moreutils}/bin/sponge";

  claude-code-bunx = pkgs.writeShellApplication {
    name = "claude-code-bunx";
    runtimeInputs = [ bun ];
    runtimeEnv = claude-code.env;
    text = builtins.readFile (
      pkgs.replaceVars ./claude-code-bunx.sh {
        inherit (claude-code) package version args;
      }
    );
  };
in
{
  programs.zsh.shellAliases = {
    cc = lib.getExe claude-code-bunx;
  };

  home.file.".claude/keybindings.json".source =
    (pkgs.formats.json { }).generate "claude-code-keybindings.json"
      claude-code.keybindings;

  home.activation.updateClaudeCodeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    settingsFile="${config.home.homeDirectory}/.claude/settings.json"

    if [[ ! -f "$settingsFile" ]]; then
      echo "Creating Claude Code settings file..."

      mkdir -p "$(dirname "$settingsFile")"
      echo "{}" > "$settingsFile"
      chmod 644 "$settingsFile"
    fi

    ${jq} ${lib.strings.escapeShellArg ''. + ${builtins.toJSON claude-code.settings} | {"$schema": .["$schema"]} + del(.["$schema"])''} "$settingsFile" | ${sponge} "$settingsFile"
  '';
}
