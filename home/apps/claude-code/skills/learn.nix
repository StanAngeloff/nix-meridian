{
  pkgs,
  ...
}:
let
  academic-forge = pkgs.academic-forge;
in
{
  home.file.".claude/skills/learn".source = "${academic-forge}/share/claude-code/skills/learn";
}
