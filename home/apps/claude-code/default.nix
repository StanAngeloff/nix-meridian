{
  config,
  lib,
  pkgs,
  ...
}:
let
  nodejs = pkgs.nodejs_24;

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
      # Learn more at https://code.claude.com/docs/en/data-usage
      DISABLE_TELEMETRY = 1;
      DISABLE_ERROR_REPORTING = 1;
      CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY = 1;
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = 1;
    };
    settings = {
      "$schema" = "https://json.schemastore.org/claude-code-settings.json";
      alwaysThinkingEnabled = true;
      effortLevel = "high";
      showThinkingSummaries = true;
      spinnerTipsEnabled = false;
      hooks = {
        Notification = [
          {
            matcher = "permission_prompt";
            hooks = [
              {
                type = "command";
                command = "${lib.getBin pkgs.pipewire}/bin/pw-play ${./audio/notifications/mixkit-clear-announce-tones-2861.mp3}";
                timeout = 5;
              }
            ];
          }
        ];
      };
      # Learn more at https://code.claude.com/docs/en/settings#sandbox-settings
      sandbox = {
        enabled = true;
        failIfUnavailable = true;
        autoAllowBashIfSandboxed = true;
        excludedCommands = [
          # GPG signing needs write access to ~/.gnupg.
          "git commit *"
        ];
        allowUnsandboxedCommands = true;
      };
      # Learn more at https://code.claude.com/docs/en/settings#attribution-settings
      attribution = {
        commit = "";
        pr = "";
      };
      statusLine = {
        type = "command";
        command = lib.getExe claude-code-statusline;
        padding = 0;
      };
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

  claude-code-npx = pkgs.writeShellApplication {
    name = "claude-code-npx";
    runtimeInputs = [
      nodejs
      pkgs.bubblewrap
      pkgs.socat
    ];
    runtimeEnv = claude-code.env;
    text = builtins.readFile (
      pkgs.replaceVars ./claude-code-npx.sh {
        inherit (claude-code) package version args;
      }
    );
  };

  claude-code-statusline = pkgs.writeShellApplication {
    name = "claude-code-statusline";
    runtimeInputs = with pkgs; [
      jq
      bc
      git
      gnused
      coreutils
    ];
    text = builtins.readFile ./statusline.sh;
  };
in
{
  programs.zsh.shellAliases = {
    cc = lib.getExe claude-code-npx;
  };

  home.file.".claude/keybindings.json".source =
    (pkgs.formats.json { }).generate "claude-code-keybindings.json"
      claude-code.keybindings;

  home.activation.updateClaudeCodeSettings =
    let
      jq = lib.getExe pkgs.jq;
      sponge = "${lib.getBin pkgs.moreutils}/bin/sponge";
    in
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
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
