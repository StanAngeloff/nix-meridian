{
  pkgs,
  ...
}:
let
  ponytail = pkgs.ponytail;
in
{
  home.file.".claude/skills/ponytail".source = "${ponytail}/share/claude-code/skills/ponytail";
}
