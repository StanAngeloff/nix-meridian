{
  lib,
  writeShellApplication,
  jq,
  ...
}:
let
  handler = writeShellApplication {
    name = "claude-profiles";
    runtimeInputs = [ jq ];
    text = builtins.readFile ./profiles.sh;
  };
in
{
  runtimeInputs = [ jq ];
  substitutions = {
    profilesHandler = lib.getExe handler;
  };
}
