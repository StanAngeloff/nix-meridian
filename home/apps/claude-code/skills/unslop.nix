{
  pkgs,
  ...
}:
let
  cursor-plugins = pkgs.cursor-plugins;
in
{
  home.file.".claude/skills/unslop".source = "${cursor-plugins}/share/claude-code/skills/unslop";
}
