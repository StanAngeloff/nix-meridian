{
  DISABLE_AUTOUPDATER = 1;
  FORCE_AUTOUPDATE_PLUGINS = 1;
  DISABLE_INSTALLATION_CHECKS = 1;
  USE_BUILTIN_RIPGREP = 0;
  MAX_THINKING_TOKENS = 64000;
  # See "[BUG] Logo and "Thinking" animation colors are dull/washed-out inside tmux" https://github.com/anthropics/claude-code/issues/35148#issuecomment-4355935411
  CLAUDE_CODE_TMUX_TRUECOLOR = 1;
  # See "[MODEL] Claude Code is unusable for complex engineering tasks with the Feb updates" https://github.com/anthropics/claude-code/issues/42796
  CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING = 1;
  CLAUDE_CODE_EFFORT_LEVEL = "max"; # This one is ignored in favor of settings.json, but I'm _hoping_ has some influence on sub-agents.
  # Learn more at https://code.claude.com/docs/en/agent-teams
  CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = 1;
  # Learn more at https://code.claude.com/docs/en/data-usage
  DISABLE_TELEMETRY = 1;
  DISABLE_ERROR_REPORTING = 1;
  CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY = 1;
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = 1;
  # Learn more at https://code.claude.com/docs/en/sub-agents#fork-the-current-conversation
  CLAUDE_CODE_FORK_SUBAGENT = 1;
}
