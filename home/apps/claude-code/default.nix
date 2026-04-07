{
  config,
  lib,
  pkgs,
  ...
}:
let
  claude-code = {
    package = "@anthropic-ai/claude-code";
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
      alwaysThinkingEnabled = true;
      effortLevel = "high";
      showThinkingSummaries = true;
      spinnerTipsEnabled = false;
    };
  };

  bun = pkgs.bun;
  jq = lib.getExe pkgs.jq;
  sponge = "${lib.getBin pkgs.moreutils}/bin/sponge";

  # Builds an alias string for an npm registry package, with optional env, version and arguments.
  mkNpmAlias =
    cfg:
    let
      envPrefix =
        if cfg ? env then
          builtins.concatStringsSep " " (
            builtins.attrValues (builtins.mapAttrs (k: v: "${k}=${builtins.toString v}") cfg.env)
          )
          + " "
        else
          "";
      version = if cfg ? version then cfg.version else "latest";
      argsSuffix = if cfg ? args then " ${cfg.args}" else "";
    in
    "${envPrefix}${lib.getBin bun}/bin/bunx --silent ${cfg.package}@${version}${argsSuffix}";
in
{
  programs.zsh.shellAliases = {
    cc = mkNpmAlias claude-code;
  };

  home.activation.updateClaudeCodeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    settingsFile="${config.home.homeDirectory}/.claude/settings.json"

    if [[ ! -f "$settingsFile" ]]; then
      echo "Creating Claude Code settings file..."

      mkdir -p "$(dirname "$settingsFile")"
      echo "{}" > "$settingsFile"
      chmod 644 "$settingsFile"
    fi

    ${jq} ${lib.strings.escapeShellArg ". + ${builtins.toJSON claude-code.settings}"} "$settingsFile" | ${sponge} "$settingsFile"
  '';
}
