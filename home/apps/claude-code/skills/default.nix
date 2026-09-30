{ config, lib, ... }:
let
  # A package that ships Claude Code skills lists them in passthru.claudeCodeSkills, under share/claude-code/skills/<name>.
  # Installing it through home.packages is then all it takes: each skill is linked into ~/.claude/skills/ here.
  skillPackages = lib.filter (package: package ? claudeCodeSkills) config.home.packages;
  shippedSkillNames = lib.concatMap (package: package.claudeCodeSkills) skillPackages;

  skillAliases = config.claude-code.skills.aliases;
  # The names each skill is linked under: its aliases, or its own name when it has none.
  linkNamesBySkillName = lib.groupBy (alias: skillAliases.${alias}) (lib.attrNames skillAliases);
in
{
  imports = [
    ./git-lines.nix
    ./learn.nix
    ./slopsift.nix
    ./unslop.nix
  ];

  options.claude-code.skills.aliases = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    example = {
      annotate = "plannotator-annotate";
    };
    description = ''
      Short slash commands for skills that packages ship, as alias = skill name.
      Claude Code takes a skill's command name from its directory, so the skill is linked into ~/.claude/skills/ under the alias instead of its own name.
      Its frontmatter `name:` still runs it and is what the suggestion list shows.
      An exact command name beats another command's alias, so an alias can take over a bundled skill's alias.
    '';
  };

  config = {
    # One definition per link, so two packages shipping the same skill name, or an alias reusing a linked name, fail evaluation instead of one winning.
    home.file = lib.mkMerge (
      lib.concatMap (
        package:
        lib.concatMap (
          skillName:
          map (linkName: {
            ".claude/skills/${linkName}".source = "${package}/share/claude-code/skills/${skillName}";
          }) (linkNamesBySkillName.${skillName} or [ skillName ])
        ) package.claudeCodeSkills
      ) skillPackages
    );

    # An alias whose skill no package ships would link nothing, so a typo or an upstream rename fails the switch instead.
    assertions = lib.mapAttrsToList (alias: skillName: {
      assertion = lib.elem skillName shippedSkillNames;
      message = "claude-code.skills.aliases.${alias}: no package in home.packages lists \"${skillName}\" in passthru.claudeCodeSkills (shipped: ${lib.concatStringsSep ", " shippedSkillNames}).";
    }) skillAliases;
  };
}
