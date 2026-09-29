{ config, lib, ... }:
let
  # A package that ships Claude Code skills lists them in passthru.claudeCodeSkills, under share/claude-code/skills/<name>.
  # Installing it through home.packages is then all it takes: each skill is linked into ~/.claude/skills/ here.
  skillPackages = lib.filter (package: package ? claudeCodeSkills) config.home.packages;
in
{
  imports = [
    ./git-lines.nix
    ./learn.nix
    ./slopsift.nix
    ./unslop.nix
  ];

  # One definition per package, so two packages shipping the same skill name fail evaluation instead of one winning.
  home.file = lib.mkMerge (
    map (
      package:
      lib.listToAttrs (
        map (
          skillName:
          lib.nameValuePair ".claude/skills/${skillName}" {
            source = "${package}/share/claude-code/skills/${skillName}";
          }
        ) package.claudeCodeSkills
      )
    ) skillPackages
  );
}
