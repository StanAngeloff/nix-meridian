{
  lib,
  writeShellApplication,
  bubblewrap,
  coreutils,
  curl,
  inotify-tools,
  jq,
  procps,
  python3,
  systemd,
  tmux,
  wwwBrowser,
  ...
}:
let
  # Same message formatting as the launcher; these commands are built separately, so each takes its own copy of the library rather than inheriting one.
  logHelpers = builtins.readFile ../../utilities/log.sh;

  # The throwaway sandbox every proof in verify.sh runs Claude Code in.
  sandbox = writeShellApplication {
    name = "claude-profiles-sandbox";
    runtimeInputs = [
      bubblewrap
      coreutils
    ];
    text = builtins.readFile ./sandbox.sh;
  };

  # `cc profiles verify`: the facts the profile layout rests on, proven against the installed Claude Code.
  verify = writeShellApplication {
    name = "claude-profiles-verify";
    runtimeInputs = [
      coreutils
      curl
      inotify-tools
      jq
      python3
      tmux
    ];
    text =
      builtins.replaceStrings
        [ "@profilesSandbox@" "@verifiedClaudeCodeVersion@" ]
        [ (lib.getExe sandbox) (import ./verified-version.nix) ]
        (logHelpers + builtins.readFile ./verify.sh);
  };

  handler = writeShellApplication {
    name = "claude-profiles";
    runtimeInputs = [
      coreutils
      jq
      procps # pgrep, for the running-instance guards
      systemd # systemctl and systemd-escape, for the running-session registry
    ];
    text =
      builtins.replaceStrings
        [ "@wwwBrowser@" "@profilesVerify@" ]
        [ (lib.getExe wwwBrowser) (lib.getExe verify) ]
        (logHelpers + builtins.readFile ./profiles.sh);
    # Every build runs the behaviour tests against the command it just built, after shellcheck; see test_profiles.py.
    derivationArgs.postCheck = ''
      PROFILES_COMMAND="$target" ${python3.interpreter} ${./test_profiles.py}
    '';
  };
in
{
  runtimeInputs = [ jq ];
  # The launcher runs `check` before every session; see hooks.sh.
  substitutions.profilesHandler = lib.getExe handler;
  subcommands = [
    {
      name = "profiles";
      handler = lib.getExe handler;
      description = "Account profiles that sessions run as (list, which, select, add, remove, migrate, check, verify)";
    }
  ];
}
