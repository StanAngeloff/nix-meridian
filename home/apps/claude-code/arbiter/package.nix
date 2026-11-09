{
  lib,
  callPackage,
  writeShellApplication,
  coreutils,
  jq,
  python3,
  cc-safety-net,
}:
# The PreToolUse arbiter the bubble's settings file registers for every tool call; see claude-arbiter.sh.
# writeShellApplication runs shellcheck at build time and sets meta.mainProgram, so lib.getExe resolves it.
let
  # The engine's configuration, a store directory checked against the engine it configures; see policy.nix.
  policy = callPackage ./policy.nix { inherit cc-safety-net; };
  # The same configuration without the request rules, for the second look's rerun, which must still find every other stop.
  policyWithoutRequestRules = callPackage ./policy.nix {
    inherit cc-safety-net;
    droppedRules = [
      "gh-api-write"
      "curl-write"
    ];
  };
in
writeShellApplication {
  name = "claude-arbiter";

  runtimeInputs = [
    coreutils
    jq
    python3
  ];

  text =
    builtins.replaceStrings
      [ "@engineExe@" "@policyPath@" "@policyWithoutRequestRulesPath@" "@classifierPath@" ]
      [
        (lib.getExe cc-safety-net)
        "${policy}"
        "${policyWithoutRequestRules}"
        "${./classify_requests.py}"
      ]
      (builtins.readFile ./claude-arbiter.sh);

  passthru = { inherit policy policyWithoutRequestRules; };
}
