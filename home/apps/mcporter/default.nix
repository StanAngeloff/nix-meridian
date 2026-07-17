{
  config,
  lib,
  pkgs,
  ...
}:
let
  mcporter-settings = {
    mcpServers = {
      slack = {
        command = lib.getExe pkgs.slack-mcp-server;
        # Learn more at https://github.com/korotovsky/slack-mcp-server/blob/v1.3.0/docs/01-authentication-setup.md#option-1-using-slack_mcp_xoxc_tokenslack_mcp_xoxd_token-browser-session
        env = {
          SLACK_MCP_XOXC_TOKEN = "\${SLACK_MCP_XOXC_TOKEN}";
          SLACK_MCP_XOXD_TOKEN = "\${SLACK_MCP_XOXD_TOKEN}";
        };
      };
      notion = {
        baseUrl = "https://mcp.notion.com/mcp";
      };
      shortcut = {
        baseUrl = "https://mcp.shortcut.com/mcp";
      };
      datadog = {
        baseUrl = "https://mcp.datadoghq.eu/api/unstable/mcp-server/mcp";
      };
    };
  };
in
{
  home.activation.updateMcporterSettings =
    let
      jq = lib.getExe pkgs.jq;
      sponge = "${lib.getBin pkgs.moreutils}/bin/sponge";
      settingsJson = builtins.toJSON mcporter-settings;
    in
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      settingsFile="${config.xdg.configHome}/mcporter/mcporter.json"

      if [[ ! -f "$settingsFile" ]]; then
        mkdir -p "$(dirname "$settingsFile")"
        echo "{}" > "$settingsFile"
        chmod 644 "$settingsFile"
      fi

      ${jq} --argjson nix ${lib.strings.escapeShellArg settingsJson} '
        . as $existing |
        ($existing + $nix) |
        .mcpServers = (($existing.mcpServers // {}) + $nix.mcpServers)
      ' "$settingsFile" | ${sponge} "$settingsFile"
    '';
}
