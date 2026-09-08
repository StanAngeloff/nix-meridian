{
  pkgs,
  ...
}:
let
  git-lines = pkgs.git-lines;
in
{
  home.packages = [
    git-lines
  ];

  home.file.".claude/skills/git-lines".source = "${git-lines}/share/claude-code/skills/git-lines";
}
