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
# Because a running session writes that file continuously, the merge below never rewrites it blindly.
let
  integrations = import ../mcp.nix { inherit lib pkgs pkgs-unstable; };
  mcpServers = lib.mapAttrs (_: integration: integration.claude.mcp) (
    lib.filterAttrs (_: integration: integration ? claude.mcp) integrations
  );
in
{
  home.activation.updateClaudeCodeMcpServers =
    let
      jq = lib.getExe pkgs.jq;
    in
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      configFile="${config.home.homeDirectory}/.claude/.claude.json"
      desired=${lib.strings.escapeShellArg (builtins.toJSON mcpServers)}

      if [[ ! -f "$configFile" ]]; then
        echo "Creating Claude Code config file..."

        mkdir -p "$(dirname "$configFile")"
        # 600, matching what Claude Code creates: this file also holds the OAuth account and machine identifiers.
        (umask 077 && echo "{}" > "$configFile")
      fi

      # Compare only the names this repository owns, so servers added by hand (claude mcp add, /mcp) neither drift nor get clobbered.
      # When nothing has changed — every rebuild after the first — the activation ends here, having only read the file.
      managed="$(${jq} -cS --argjson desired "$desired" '(.mcpServers // {}) | with_entries(select(.key | in($desired)))' "$configFile")"

      if [[ "$managed" != "$(${jq} -cS . <<<"$desired")" ]]; then
        for attempt in 1 2 3; do
          # Claude Code publishes its writes by renaming a fresh file into place, so any concurrent write changes the inode, the size, or the nanosecond mtime.
          # Re-reading the fingerprint immediately before the rename narrows the window in which such a write could be lost to the rename itself.
          fingerprint="$(stat -c '%i:%s:%.9Y' "$configFile")"

          tmpFile="$(mktemp "$configFile.nix-XXXXXX")"
          ${jq} --argjson desired "$desired" '.mcpServers = ((.mcpServers // {}) + $desired)' "$configFile" > "$tmpFile"
          chmod --reference="$configFile" "$tmpFile"

          if [[ "$fingerprint" == "$(stat -c '%i:%s:%.9Y' "$configFile")" ]]; then
            mv "$tmpFile" "$configFile"
            break
          fi

          rm -f "$tmpFile"

          if [[ "$attempt" == 3 ]]; then
            echo "Claude Code MCP servers left unchanged: $configFile kept being written during the merge (a session is running)." >&2
          fi
        done
      fi
    '';
}
