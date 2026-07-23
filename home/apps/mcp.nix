{
  lib,
  pkgs,
}:
# Single registry of external service integrations, viewed per consuming tool. Each consumer imports this file and projects its own facet, so adding an integration is one entry here:
#   .mcporter        — connection config for the MCPorter aggregator (home/apps/mcporter)
#   .claude.ask      — Claude Code permission-prompt globs (permissions.ask); these prompt even in auto mode / --dangerously-skip-permissions
#   .claude.secrets  — env-var names the Claude Code bubble resolves from the keyring host-side and injects (bubble keyringVariables)
{
  # ── MCPorter-managed servers ──
  slack = {
    mcporter = {
      command = lib.getExe pkgs.slack-mcp-server;
      # Learn more at https://github.com/korotovsky/slack-mcp-server/blob/v1.3.0/docs/01-authentication-setup.md#option-1-using-slack_mcp_xoxc_tokenslack_mcp_xoxd_token-browser-session
      env = {
        SLACK_MCP_XOXC_TOKEN = "\${SLACK_MCP_XOXC_TOKEN}";
        SLACK_MCP_XOXD_TOKEN = "\${SLACK_MCP_XOXD_TOKEN}";
      };
    };
  };

  notion = {
    mcporter = {
      baseUrl = "https://mcp.notion.com/mcp";
    };
    claude = {
      ask = [
        "mcp__notion__notion-create-*"
        "mcp__notion__notion-update-*"
        "mcp__notion__notion-duplicate-*"
        "mcp__notion__notion-move-*"
      ];
    };
  };

  shortcut = {
    mcporter = {
      baseUrl = "https://mcp.shortcut.com/mcp";
    };
    # noun-verb tool names, so globs anchor on the verb suffix
    claude = {
      ask = [
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
  };

  datadog = {
    mcporter = {
      baseUrl = "https://mcp.datadoghq.eu/api/unstable/mcp-server/mcp";
    };
    claude = {
      ask = [
        "mcp__datadog__create_*"
        "mcp__datadog__edit_*"
        "mcp__datadog__upsert_*"
      ];
    };
  };

  # ── Claude Code MCPs configured outside MCPorter ──
  # GitHub: the MCP server (~/.claude.json, GH_TOKEN-authenticated) plus the gh/git CLI, its command-line sibling — both gated together.
  github = {
    claude = {
      ask = [
        # gh / git CLI — externally-visible actions
        "Bash(git push)"
        "Bash(git push *)"
        "Bash(gh pr create *)"
        "Bash(gh pr merge *)"
        "Bash(gh pr close *)"
        "Bash(gh pr reopen *)"
        "Bash(gh pr comment *)"
        "Bash(gh pr review *)"
        "Bash(gh pr edit *)"
        "Bash(gh pr ready *)"
        "Bash(gh issue create *)"
        "Bash(gh issue close *)"
        "Bash(gh issue reopen *)"
        "Bash(gh issue comment *)"
        "Bash(gh issue edit *)"
        "Bash(gh release create *)"
        "Bash(gh release edit *)"
        "Bash(gh release delete *)"
        "Bash(gh repo create *)"
        "Bash(gh repo delete *)"
        "Bash(gh repo edit *)"
        "Bash(gh api *)"
        "Bash(gh workflow run *)"
        "Bash(gh secret set *)"
        "Bash(gh variable set *)"
        # GitHub MCP — writes (verb-first names, so prefix globs)
        "mcp__github__create_*"
        "mcp__github__update_*"
        "mcp__github__delete_*"
        "mcp__github__merge_*"
        "mcp__github__push_*"
        "mcp__github__fork_*"
        "mcp__github__add_*"
        "mcp__github__assign_*"
        "mcp__github__request_*"
        "mcp__github__run_*"
        "mcp__github__*_write"
      ];
      # ~/.claude.json carries only a "Bearer ${GH_TOKEN}" placeholder; the bubble resolves the real token host-side.
      secrets = [ "GH_TOKEN" ];
    };
  };

  # CircleCI: project-local MCP, CIRCLECI_TOKEN-authenticated.
  circleci = {
    claude = {
      ask = [
        "mcp__circleci-mcp-server__rerun_workflow"
        "mcp__circleci-mcp-server__run_pipeline"
        "mcp__circleci-mcp-server__run_rollback_pipeline"
        "mcp__circleci-mcp-server__run_evaluation_tests"
      ];
      secrets = [ "CIRCLECI_TOKEN" ];
    };
  };

  sentry = {
    mcporter = {
      baseUrl = "https://mcp.sentry.dev/mcp";
    };
    claude = {
      ask = [
        "mcp__sentry__execute_sentry_tool"
      ];
    };
  };

  # Slack via claude.ai's managed MCP — a distinct tool namespace from the local slack server above.
  slack-ai = {
    claude = {
      ask = [
        "mcp__claude_ai_Slack__slack_send_message"
        "mcp__claude_ai_Slack__slack_send_message_draft"
        "mcp__claude_ai_Slack__slack_schedule_message"
        "mcp__claude_ai_Slack__slack_add_reaction"
        "mcp__claude_ai_Slack__slack_create_conversation"
        "mcp__claude_ai_Slack__slack_create_canvas"
        "mcp__claude_ai_Slack__slack_update_canvas"
      ];
    };
  };
}
