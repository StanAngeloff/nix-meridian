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

  # Claude Code follows this symlink and reads SKILL.md straight from the store,
  # so the prompt it ingests is the one pinned in pkgs/git-lines/package.nix — read-only,
  # and out of reach of the plugin updater.
  home.file.".claude/skills/git-lines".source = "${git-lines}/share/claude-code/skills/git-lines";
}
