{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:
# Claude Code's user-scope MCP server list, projected from the integration registry (../mcp.nix — different file, same name).
# These live in ~/.claude/.claude.json rather than settings.json: that file predates settings.json and is where Claude Code keeps
# its mutable state (session history, costs, feature caches), with mcpServers a declarative island in the middle of it.
let
  inherit (import ./json-utils.nix { inherit lib pkgs; }) mergeIntoTargetFile;
  integrations = import ../mcp.nix { inherit lib pkgs pkgs-unstable; };
  mcpServers = lib.mapAttrs (_: integration: integration.claude.mcp) (
    lib.filterAttrs (_: integration: integration ? claude.mcp) integrations
  );
  claudeConfigPath = lib.escapeShellArg "${config.home.homeDirectory}/.claude";
in
{
  # Guarded against a running session's own writes; see ./json-utils.nix.
  # Each account profile keeps its own .claude.json (bubble/modules/profiles) and the shared path links one of them, so the
  # servers go into every profile's copy, never through the link; before the profile migration, into the shared file itself.
  home.activation.updateClaudeCodeMcpServers = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    claudeConfigFiles=()
    if [[ -L ${claudeConfigPath}/.claude.json ]]; then
      for profileDirectory in ${claudeConfigPath}/profiles/*/; do
        if [[ ! -L "''${profileDirectory%/}" && -f "''${profileDirectory}.claude.json" ]]; then
          claudeConfigFiles+=("''${profileDirectory}.claude.json")
        fi
      done
    else
      claudeConfigFiles+=(${claudeConfigPath}/.claude.json)
    fi
    for targetFile in "''${claudeConfigFiles[@]}"; do
      ${mergeIntoTargetFile {
        label = "Claude Code MCP servers";
        # 600, matching what Claude Code creates: this file also holds the OAuth account and machine identifiers.
        mode = "600";
        # Merged per server name, so servers added by hand (claude mcp add, /mcp) neither drift nor get clobbered.
        filter = ".mcpServers = ((.mcpServers // { }) + ${builtins.toJSON mcpServers})";
      }}
    done
  '';
}
