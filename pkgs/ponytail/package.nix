{
  lib,
  fetchFromGitHub,
  applyPatches,
  runCommand,
  skillDigests ? {
    ponytail = "1316a2f3f95741d2300b116fe0c2d81ce4a9568656ed0a62643f54aaf09957f2";
  },
}:
let
  pname = "ponytail";
  version = "4.13.0";

  src = fetchFromGitHub {
    owner = "DietrichGebert";
    repo = "ponytail";
    tag = "v${version}";
    hash = "sha256-sf8WLd7PFXGRM7+LGaXDT/exA0YU9Ld8U5uZFBEqM/k=";
  };

  # Upstream's description has Claude load the skill on its own for any coding task; the patch restricts it to explicit requests.
  # The digests pin the unpatched upstream files.
  patchedSrc = applyPatches {
    name = "${pname}-${version}-source";
    inherit src;
    patches = [ ./explicit-invocation-only.patch ];
  };

  skills = lib.attrNames skillDigests;
in
runCommand "${pname}-${version}" { } (
  lib.concatStringsSep "\n" (
    map (name: ''
      echo "${skillDigests.${name}}  ${src}/skills/${name}/SKILL.md" | sha256sum -c -
      install -Dm444 ${patchedSrc}/skills/${name}/SKILL.md -t $out/share/claude-code/skills/${name}/
      install -Dm444 ${src}/LICENSE -t $out/share/claude-code/skills/${name}/
    '') skills
  )
)
