{ pkgs }:
# High-precedence CLI --settings layer for bubbled sessions.
(pkgs.formats.json { }).generate "claude-bubble-settings.json" {
  sandbox = {
    # The bubble replaces the inner Bash sandbox, whose false positives trained constant dangerouslyDisableSandbox use.
    enabled = false;
  };
}
