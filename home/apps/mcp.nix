{
  lib,
  pkgs,
  pkgs-unstable,
}:
# Single registry of external service integrations, viewed per consuming tool. Each consumer imports this file and projects its own facet, so adding an integration is one entry here:
#   .mcporter        — connection config for the MCPorter aggregator (home/apps/mcporter)
#   .claude.mcp      — Claude Code server definition, merged into the user scope of ~/.claude/.claude.json (home/apps/claude-code/mcp.nix)
#   .claude.ask      — Claude Code permission-prompt globs (permissions.ask); these prompt even in auto mode / --dangerously-skip-permissions
#   .claude.allow    — (deprecated) Claude Code auto-approve globs (permissions.allow) for the read-only half of a server; ask beats allow, so the two must not overlap
#   .claude.secrets  — env-var names the Claude Code bubble resolves from the keyring host-side and injects (bubble keyringVariables)
let
  # One stdio server, two consumers. Claude Code and MCPorter share the schema, so the definition is written once.
  perplexity-server = {
    command = lib.getExe pkgs-unstable.perplexity-mcp;
    env = {
      PERPLEXITY_API_KEY = "\${PERPLEXITY_API_KEY}";
    };
  };

  # `gh api` is one command reaching every GitHub REST and GraphQL endpoint, so gating it by name gates reading too.
  # It defaults to GET. A GET changes nothing on GitHub, so we gate on the method.
  # Two flags take a call off that default: an explicit method override and a body field.
  # gh switches the method to POST as soon as any field is present, so `-f ref=v0.12.0` turns a plain file read into a POST.
  # An invocation carrying none of these flags is a read and runs unprompted.
  #
  # The `-X` rules match the flag whole rather than one rule per write method. Catching `-X GET` too costs a handful of prompts.
  # Enumerating POST/PUT/PATCH/DELETE instead would let an unexpected spelling through unasked.
  # Each flag needs both forms, because the `*` in "gh api * -f*" cannot match the empty gap in "gh api -f body=x".
  #
  # GraphQL carries its document in `-f query=`, so reads and mutations are one shape here. Both ask.
  ghApiAsk =
    lib.concatMap
      (flag: [
        "Bash(gh api ${flag}*)"
        "Bash(gh api * ${flag}*)"
      ])
      [
        "-X"
        "--method"
        "-f"
        "-F"
        "--field"
        "--raw-field"
        "--input"
      ];

  # Destructive local git commands: each discards work that has no other copy, so each one asks.
  # Prefix rules cannot spare the harmless forms: `git restore --staged` and `git clean -n` ask too.
  # Each form comes twice, right after the subcommand and after other arguments, for the reason ghApiAsk gives.
  gitDestructiveAsk = [
    "Bash(git checkout -- *)"
    "Bash(git checkout * -- *)"
    "Bash(git checkout .)"
    "Bash(git checkout * .)"
    "Bash(git checkout -f*)"
    "Bash(git checkout * -f*)"
    "Bash(git checkout --force*)"
    "Bash(git checkout * --force*)"
    "Bash(git restore *)"
    "Bash(git clean *)"
    "Bash(git stash drop*)"
    "Bash(git stash clear*)"
  ];
in
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
  # GitHub: the MCP server (GH_TOKEN-authenticated) plus the gh/git CLI, its command-line sibling — both gated together.
  github = {
    claude = {
      mcp = {
        type = "http";
        url = "https://api.githubcopilot.com/mcp";
        headers = {
          Authorization = "Bearer \${GH_TOKEN}";
        };
      };
      ask = [
        # gh / git CLI — externally-visible actions
        "Bash(git push)"
        "Bash(git push *)"
        # git's global options sit before the subcommand.
        "Bash(git -C * push*)"
        "Bash(git -c * push*)"
        "Bash(git reset)"
        "Bash(git reset *)"
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
      ]
      # gh api is gated by request shape rather than by subcommand name. See ghApiAsk above.
      ++ ghApiAsk
      # git's destructive local commands. See gitDestructiveAsk above.
      ++ gitDestructiveAsk;
      # ~/.claude/.claude.json carries only a "Bearer ${GH_TOKEN}" placeholder; the bubble resolves the real token host-side.
      secrets = [ "GH_TOKEN" ];
    };
  };

  # Google Developer Knowledge: project-local HTTP MCP, API-key-authenticated. Secret only; server config is project-managed.
  google-developer-knowledge = {
    claude = {
      secrets = [ "GOOGLE_DEVELOPER_KNOWLEDGE_API_KEY" ];
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

  # LaunchDarkly: project-local MCP (@launchdarkly/mcp-server), LAUNCHDARKLY_API_TOKEN-authenticated.
  launchdarkly = {
    claude = {
      # verb-first kebab-case names, so prefix globs. At 0.6.2 the server mounts 20 tools; these three globs cover all 10 that write, and every remaining one is a get-*/list-*.
      ask = [
        "mcp__launchdarkly__create-*"
        "mcp__launchdarkly__update-*"
        "mcp__launchdarkly__delete-*"
      ];
      secrets = [ "LAUNCHDARKLY_API_TOKEN" ];
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

  # Perplexity's official MCP server (@perplexity-ai/mcp-server), pinned via unstable for determinism. Every tool call hits the paid API, so only the cheap perplexity_search runs unprompted; ask/reason/research are gated.
  perplexity = {
    mcporter = perplexity-server;
    claude = {
      mcp = perplexity-server;
      ask = [
        #"mcp__perplexity__perplexity_ask" – let Claude ask the questions, don't worry about the cost of the API calls (Ask is cheap)
        "mcp__perplexity__perplexity_reason"
        "mcp__perplexity__perplexity_research"
      ];
      secrets = [ "PERPLEXITY_API_KEY" ];
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
        "mcp__claude_ai_Slack__slack_create_list"
        "mcp__claude_ai_Slack__slack_update_list"
        "mcp__claude_ai_Slack__slack_add_list_record"
        "mcp__claude_ai_Slack__slack_update_list_record"
        "mcp__claude_ai_Slack__slack_get_file_upload_url"
        "mcp__claude_ai_Slack__slack_complete_file_upload"
      ];
    };
  };

  # Google Workspace via claude.ai's managed connectors. Each server's writes are named one tool at a time; every remaining tool reads.
  google-workspace-ai = {
    claude = {
      ask = [
        "mcp__claude_ai_Google_Calendar__create_event"
        "mcp__claude_ai_Google_Calendar__update_event"
        "mcp__claude_ai_Google_Calendar__delete_event"
        "mcp__claude_ai_Google_Calendar__respond_to_event"
        "mcp__claude_ai_Google_Drive__create_file"
        "mcp__claude_ai_Google_Drive__copy_file"
        "mcp__claude_ai_Google_Drive__update_file"
        "mcp__claude_ai_Google_Drive__share_file"
        "mcp__claude_ai_Google_Drive__trash_file"
        "mcp__claude_ai_Google_Docs__update_doc"
        "mcp__claude_ai_Google_Sheets__insert_dimension"
        "mcp__claude_ai_Google_Sheets__update_formulas"
        "mcp__claude_ai_Google_Sheets__update_spreadsheet"
        "mcp__claude_ai_Google_Sheets__update_values"
        "mcp__claude_ai_Google_Slides__update_presentation"
      ];
    };
  };

  # Claude Docs via claude.ai's managed connector: create, update, batch and delete change a shared doc; guide, query, read and export read.
  claude-docs-ai = {
    claude = {
      ask = [
        "mcp__claude_ai_Claude_Docs__create"
        "mcp__claude_ai_Claude_Docs__update"
        "mcp__claude_ai_Claude_Docs__batch"
        "mcp__claude_ai_Claude_Docs__delete"
      ];
    };
  };

  # Looker via claude.ai's managed connector. The writes change LookML files, dashboards, looks or the session's dev mode.
  looker-ai = {
    claude = {
      ask = [
        "mcp__claude_ai_Looker__add_*"
        "mcp__claude_ai_Looker__create_*"
        "mcp__claude_ai_Looker__update_*"
        "mcp__claude_ai_Looker__delete_*"
        "mcp__claude_ai_Looker__make_*"
        "mcp__claude_ai_Looker__dev_mode"
      ];
    };
  };

  # Figma: project-local MCP. create_session is left out because every read needs one; the other creates, and every send, update,
  # upload, generate and run, write to a Figma file or start paid generation.
  figma = {
    claude = {
      ask = [
        "mcp__figma__add_*"
        "mcp__figma__create_new_file"
        "mcp__figma__create_generative_plugin"
        "mcp__figma__create_shader"
        "mcp__figma__update_*"
        "mcp__figma__upload_assets"
        "mcp__figma__send_*"
        "mcp__figma__use_figma"
        "mcp__figma__generate_*"
        "mcp__figma__weave_run_*"
        "mcp__figma__weave_upload_asset"
        "mcp__figma__weave_cancel_tool_run"
      ];
    };
  };
}
