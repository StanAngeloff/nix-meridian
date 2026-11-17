{
  writeShellApplication,
  coreutils,
  jq,
}:
# Away mode (/away): the PermissionRequest command hook that denies an unanswered prompt (../../notifications.nix);
# the mod beside it tells it when. See claude-away.sh and hooks/register.tsx.
# writeShellApplication runs shellcheck at build time and sets meta.mainProgram, so lib.getExe resolves it.
writeShellApplication {
  name = "claude-away";

  runtimeInputs = [
    coreutils
    jq
  ];

  text = builtins.readFile ./claude-away.sh;
}
