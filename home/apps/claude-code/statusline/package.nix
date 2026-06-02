{
  writeShellApplication,
  jq,
  bc,
  git,
  gnused,
  coreutils,
}:
writeShellApplication {
  name = "claude-code-statusline";
  runtimeInputs = [
    jq
    bc
    git
    gnused
    coreutils
  ];
  text = builtins.readFile ./statusline.sh;
}
