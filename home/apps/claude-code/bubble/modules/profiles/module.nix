{
  lib,
  writeShellApplication,
  jq,
  procps,
  ...
}:
let
  handler = writeShellApplication {
    name = "claude-profiles";
    runtimeInputs = [
      jq
      procps # pgrep, for the running-instance guard
    ];
    # Same message formatting as the launcher; this command is built separately, so it takes its own copy of the library rather than inheriting one.
    text = builtins.readFile ../../utilities/log.sh + builtins.readFile ./profiles.sh;
  };
in
{
  runtimeInputs = [ jq ];
  substitutions = {
    profilesHandler = lib.getExe handler;
  };
}
