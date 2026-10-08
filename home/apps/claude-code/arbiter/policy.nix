{
  lib,
  runCommand,
  fetchFromGitHub,
  jq,
  cc-safety-net,
}:
# The engine's configuration directory, handed to it as CC_SAFETY_NET_HOME: ./cc-safety-net in the engine's own layout, plus the
# official rulebooks rule.json names without a local copy. It lands in the store, so no session can loosen it.
#
# JSON takes no comments, so the reasons behind policy.json are here; each rule carries its own reason.
# - The standard level stops only what it recognises. Strict would also deny every command it cannot fully verify, and that
#   includes the heredoc-fed Python scripts sessions write all day.
# - /tmp and /data/tmp are scratch space, where recursive deletes need no confirmation.
# - The dynamic-source rules are off: a command run through a variable cannot be inspected, and asking every time buys little.
#   CI approvals are the exception, caught by a native ask rule in ../../../mcp.nix. A shell running a script named by a
#   variable (`bash "$SCRIPT"`) still stops: the engine's own analysis raises that (analysis.dynamic-shell-source), and no
#   policy switches it off.
# - Project .env and .npmrc files hold local development settings, never these credentials, so their secret rules are off.
# - The deny paths add credential stores the built-in rules miss; those already cover SSH keys, ~/.aws, gh, kube, docker and
#   gcloud configuration, .netrc and the coding agents' own credentials.
#
# Learn more at https://github.com/kenryu42/cc-safety-net (`cc-safety-net rule doc` prints the rulebook reference).
let
  officialRulebooks = fetchFromGitHub {
    owner = "cc-safety-net";
    repo = "rulebooks";
    rev = "d1fc329f00f1c8068f0ce57a855508043981f7c7";
    hash = "sha256-UnHxoW0cdsq/jkZsv8IG9vAG2eEeIs9jyItXuiMTmAc=";
  };
  officialRulebookNames = lib.filter (
    name: !builtins.pathExists ./cc-safety-net/rules/${name}
  ) (lib.importJSON ./cc-safety-net/rules/rule.json).rules;

  # The engine skips an invalid policy or rulebook without a word, so the build proves that each file loads:
  # every sample command must come back with the rule named here, or with no stop at all.
  samples = {
    "git push origin main" = "custom.arbiter-writes/git-push";
    "git -C /srv/repository push origin main" = "custom.arbiter-writes/git-push";
    "x=$(gh api -X POST repos/o/r/issues/1/comments -f body=hi)" = "custom.arbiter-writes/gh-api-write";
    "gh api repos/o/r/pulls --jq .[].number" = "none";
    "curl -s -X POST https://example.com/api -d x" = "custom.arbiter-writes/curl-write";
    "curl -fsSL https://example.com/install.sh" = "none";
    "kubectl -n production delete pod web-1" = "custom.arbiter-writes/kubectl-write";
    "declare -x" = "custom.arbiter-flags/declare-exported";
    "aws s3 rm s3://bucket/key" = "custom.aws/block-aws-s3-rm";
    "terraform destroy" = "custom.terraform/block-terraform-destroy";
    "gcloud projects delete example" = "custom.gcloud/block-gcloud-projects-delete";
    "strace -f git reset --hard" = "git.reset-hard";
    "cat ~/.gnupg/pubring.kbx" = "secret.deny-path";
    "cat .env.development.local" = "none";
    "cat .npmrc" = "none";
    "git stash -u" = "custom.arbiter/git-stash-untracked";
    "git stash push -u -m wip" = "custom.arbiter/git-stash-untracked";
    "git stash show --include-untracked" = "none";
    "rm -rf /tmp/scratch" = "none";
  };
in
runCommand "cc-safety-net-policy" { nativeBuildInputs = [ jq ]; } ''
  cp -R ${./cc-safety-net} $out
  chmod -R u+w $out
  ${lib.concatMapStrings (name: ''
    install -Dm644 ${officialRulebooks}/.cc-safety-net/rules/${name}/rulebook.json $out/rules/${name}/rulebook.json
  '') officialRulebookNames}
  # Read-only, as in use: the engine would otherwise write its compile cache into CC_SAFETY_NET_HOME.
  chmod -R a-w $out

  mkdir home
  ${lib.concatStrings (
    lib.mapAttrsToList (command: expected: ''
      answered=$(jq -cn --arg command ${lib.escapeShellArg command} --arg cwd "$PWD" \
          '{hook_event_name: "PreToolUse", permission_mode: "default", cwd: $cwd, tool_name: "Bash", tool_input: {command: $command}}' |
        HOME=$PWD/home CC_SAFETY_NET_HOME=$out CC_SAFETY_NET_NO_UPDATE_CHECK=1 ${lib.getExe cc-safety-net} hook --coding-cli |
        jq -r '.hookSpecificOutput.permissionDecisionReason | (capture("Rule: (?<id>[^\n]+)") | .id) // "a stop without a rule"')
      if [[ "''${answered:-none}" != ${lib.escapeShellArg expected} ]]; then
        echo "cc-safety-net answered ''${answered:-none}, expected ${expected}:" ${lib.escapeShellArg command} >&2
        exit 1
      fi
    '') samples
  )}
''
