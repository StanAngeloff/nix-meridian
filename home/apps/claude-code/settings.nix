{ claude-code-statusline }:
{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:
let
  inherit (import ./json-utils.nix { inherit lib pkgs; }) mergeIntoLiveFile;
  integrations = import ../mcp.nix { inherit lib pkgs pkgs-unstable; };
  # Marketplaces plugins may come from, and which of their plugins load in every session; see ./marketplaces.nix.
  trustedMarketplaces = import ./marketplaces.nix;
  marketplaces = lib.mapAttrs (_: marketplace: {
    source = {
      source = "github";
      repo = marketplace.repo;
    };
  }) trustedMarketplaces;
  enabledPlugins = lib.listToAttrs (
    lib.concatLists (
      lib.mapAttrsToList (
        name: marketplace: map (plugin: lib.nameValuePair "${plugin}@${name}" true) marketplace.plugins
      ) trustedMarketplaces
    )
  );
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
    # Auto mode (enabled by the cc alias) routes tool calls through a classifier. We do NOT customize the classifier:
    # its built-in rules are a comprehensive backstop, it already trusts the repo you're working in, and the real checkpoint is permissions.ask below.
    # classifyAllShell is deliberately left OFF — routing every command (even ls/cat) through the classifier was far too slow.
    # Any autoMode.* override would go here, user scope only.
    #
    # Learn more at https://code.claude.com/docs/en/auto-mode-config
    #
    # Skip the one-time auto-mode opt-in dialog.
    skipAutoPermissionPrompt = true;
    # Human checkpoint. ask rules are evaluated BEFORE the classifier and always prompt — in every mode,
    # including auto and --dangerously-skip-permissions — regardless of whether the action was explicitly requested.
    # This is the deterministic gate for anything with an external side effect done on our behalf.
    # Precedence is deny > ask > allow (specificity is ignored), so writes live here while reads stay in the project-scope allow list.
    #
    # Learn more at https://code.claude.com/docs/en/permissions
    permissions = {
      # Environment dumps are how live credentials reach transcripts: the bubble injects keyring secrets as environment variables,
      # so this output writes them verbatim into the session log, which outlives the process by years.
      # Denied rather than asked because printing the whole environment is never the point —
      # the question is always whether one variable is set, which `[[ -n "$NAME" ]]` answers without disclosing anything.
      #
      # This is a speed bump, not a boundary. Rules match the command prefix, so `bash -c 'echo $NAME'` still gets through,
      # and rules do not apply to commands the user runs with `!` at all.
      #
      # NOTE: `env VAR=value command` is caught as collateral; use the shell's own `VAR=value command` instead.
      deny = [
        "Bash(env)"
        "Bash(env *)"
        "Bash(printenv)"
        "Bash(printenv *)"
        "Bash(export -p)"
      ];
      ask = lib.concatMap (integration: integration.claude.ask or [ ]) (lib.attrValues integrations);
    };
    # Learn more at https://code.claude.com/docs/en/settings#attribution-settings
    attribution = {
      commit = "";
      pr = "";
    };
    viewMode = "verbose";
    statusLine = {
      type = "command";
      command = lib.getExe claude-code-statusline;
      padding = 0;
    };
    # Learn more at https://code.claude.com/docs/en/claude-directory#cleaned-up-automatically
    cleanupPeriodDays = 18250; # 50 years, effectively never
    footerLinksRegexes = [
      {
        type = "regex";
        pattern = "\\bsc-(?<id>\\d+)\\b";
        url = "https://app.shortcut.com/story/{id}";
        label = "sc-{id}";
      }
    ];
    promptSuggestionEnabled = false;
    spellcheck = {
      enabled = true;
      language = "en_GB";
    };
    voice = {
      enabled = false; # Don't hijack the <Space> key for voice input.
    };
  };
in
{
  # Guarded against a running session's own writes; see ./json-utils.nix.
  home.activation.updateClaudeCodeSettings =
    lib.hm.dag.entryAfter [ "writeBoundary" ]
      (mergeIntoLiveFile {
        file = "${config.home.homeDirectory}/.claude/settings.json";
        label = "Claude Code settings";
        # extraKnownMarketplaces and enabledPlugins merge per key rather than wholesale, because /plugin writes those same
        # two keys: entries added by hand neither drift nor get clobbered. Everything else here is ours to replace.
        filter = ''
          . + ${builtins.toJSON settings}
          | .extraKnownMarketplaces = ((.extraKnownMarketplaces // { }) + ${builtins.toJSON marketplaces})
          | .enabledPlugins = ((.enabledPlugins // { }) + ${builtins.toJSON enabledPlugins})
          | {"$schema": .["$schema"]} + del(.["$schema"])
        '';
      });
}
