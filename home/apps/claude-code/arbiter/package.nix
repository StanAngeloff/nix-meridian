{
  lib,
  callPackage,
  writeShellApplication,
  coreutils,
  jq,
  cc-safety-net,
}:
# The PreToolUse arbiter the bubble's settings file registers for every tool call; see claude-arbiter.sh.
# writeShellApplication runs shellcheck at build time and sets meta.mainProgram, so lib.getExe resolves it.
let
  # The engine's configuration, a store directory checked against the engine it configures; see policy.nix.
  policy = callPackage ./policy.nix { inherit cc-safety-net; };
in
writeShellApplication {
  name = "claude-arbiter";

  runtimeInputs = [
    coreutils
    jq
  ];

  text =
    builtins.replaceStrings [ "@engineExe@" "@policyPath@" ] [ (lib.getExe cc-safety-net) "${policy}" ]
      (builtins.readFile ./claude-arbiter.sh);

  passthru = { inherit policy; };
}
