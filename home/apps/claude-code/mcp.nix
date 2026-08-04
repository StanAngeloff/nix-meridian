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
  inherit (import ./json-utils.nix { inherit lib pkgs; }) mergeIntoLiveFile;
  integrations = import ../mcp.nix { inherit lib pkgs pkgs-unstable; };
  mcpServers = lib.mapAttrs (_: integration: integration.claude.mcp) (
    lib.filterAttrs (_: integration: integration ? claude.mcp) integrations
  );
in
{
  # Guarded against a running session's own writes; see ./json-utils.nix.
  home.activation.updateClaudeCodeMcpServers =
    lib.hm.dag.entryAfter [ "writeBoundary" ]
      (mergeIntoLiveFile {
        file = "${config.home.homeDirectory}/.claude/.claude.json";
        label = "Claude Code MCP servers";
        # 600, matching what Claude Code creates: this file also holds the OAuth account and machine identifiers.
        mode = "600";
        # Merged per server name, so servers added by hand (claude mcp add, /mcp) neither drift nor get clobbered.
        filter = ".mcpServers = ((.mcpServers // { }) + ${builtins.toJSON mcpServers})";
      });
}
