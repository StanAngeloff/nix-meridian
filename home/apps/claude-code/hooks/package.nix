{
  writeShellApplication,
  jq,
  tmux,
}:
# Wrap the hook dispatch script with jq + tmux on PATH.
# writeShellApplication runs shellcheck at build time and sets meta.mainProgram, so lib.getExe resolves it.
writeShellApplication {
  name = "claude-tmux-state";

  runtimeInputs = [
    jq
    tmux
  ];

  text = builtins.readFile ./claude-tmux-state.sh;
}
