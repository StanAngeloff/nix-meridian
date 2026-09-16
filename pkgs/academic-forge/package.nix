{
  lib,
  fetchFromGitHub,
  runCommand,
  skillDigests ? {
    learn = "dd79b135afec2994f53065805d6dbca70b5c7175109a656503416c62f2da1201";
  },
}:
let
  pname = "academic-forge";
  version = "0-unstable-2026-09-16";

  src = fetchFromGitHub {
    owner = "HughYau";
    repo = "AcademicForge";
    rev = "01b6d90c5b50ba0aa48b6564e45ee4a0ade9487c";
    hash = "sha256-ZJo374owr0zckU3hfLQvyionLGR0chGnYKtwELXV4K4=";
  };

  skills = lib.attrNames skillDigests;
in
runCommand "${pname}-${version}" { } (
  lib.concatStringsSep "\n" (
    map (name: ''
      echo "${skillDigests.${name}}  ${src}/skills/claude-science/${name}/SKILL.md" | sha256sum -c -
      install -Dm444 ${src}/skills/claude-science/${name}/SKILL.md -t $out/share/claude-code/skills/${name}/
      install -Dm444 ${src}/skills/claude-science/${name}/LICENSE.txt -t $out/share/claude-code/skills/${name}/
    '') skills
  )
)
