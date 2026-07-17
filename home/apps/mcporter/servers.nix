{
  lib,
  pkgs,
}:
{
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
    claudeAsk = [
      "mcp__notion__notion-create-*"
      "mcp__notion__notion-update-*"
      "mcp__notion__notion-duplicate-*"
      "mcp__notion__notion-move-*"
    ];
  };
  shortcut = {
    baseUrl = "https://mcp.shortcut.com/mcp";
    # noun-verb tool names, so globs anchor on the verb suffix
    claudeAsk = [
      "mcp__shortcut__*-create"
      "mcp__shortcut__*-create-*"
      "mcp__shortcut__*-update"
      "mcp__shortcut__*-update-*"
      "mcp__shortcut__*-delete"
      "mcp__shortcut__*-add-*"
      "mcp__shortcut__*-remove-*"
      "mcp__shortcut__*-set-*"
      "mcp__shortcut__*-assign-*"
      "mcp__shortcut__*-unassign-*"
      "mcp__shortcut__*-upload-*"
    ];
  };
  datadog = {
    baseUrl = "https://mcp.datadoghq.eu/api/unstable/mcp-server/mcp";
    claudeAsk = [
      "mcp__datadog__create_*"
      "mcp__datadog__edit_*"
      "mcp__datadog__upsert_*"
    ];
  };
}
