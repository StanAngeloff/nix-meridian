{ claude-code-statusline }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  settings = {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    alwaysThinkingEnabled = true;
    effortLevel = "high";
    showThinkingSummaries = true;
    spinnerTipsEnabled = false;
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
    # Learn more at https://code.claude.com/docs/en/claude-directory#cleaned-up-automatically
    cleanupPeriodDays = 18250; # 50 years, effectively never
  };
in
{
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

      ${jq} ${lib.strings.escapeShellArg ''. + ${builtins.toJSON settings} | {"$schema": .["$schema"]} + del(.["$schema"])''} "$settingsFile" | ${sponge} "$settingsFile"
    '';
}
