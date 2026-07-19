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
    text = builtins.readFile ./profiles.sh;
  };
in
{
  runtimeInputs = [ jq ];
  substitutions = {
    profilesHandler = lib.getExe handler;
  };
}
