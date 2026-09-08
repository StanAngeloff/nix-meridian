{
  pkgs,
  ...
}:
let
  slopsift = pkgs.slopsift;
in
{
  home.packages = [
    slopsift
  ];

  home.file.".claude/skills/slopsift".source = "${slopsift}/share/claude-code/skills/slopsift";
}
