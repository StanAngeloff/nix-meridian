{
  lib,
  fetchFromGitHub,
  runCommand,
  # Each skill Claude ingests is pinned by content, not just by source revision.
  # A version bump that changes a SKILL.md will fail the build until the corresponding
  # digest here is updated — so rewording what Claude is told stays a deliberate act.
  # Update a digest only after reading the upstream diff for that skill.
  skillDigests ? {
    unslop = "c6d2572294d933a428211921069e9a248490e9b466ca59437cb4d9de248600ca";
  },
}:
let
  pname = "cursor-plugins";
  version = "0-unstable-2026-09-07";

  src = fetchFromGitHub {
    owner = "cursor";
    repo = "plugins";
    rev = "71ed0d1076fec562c1b74ee353121a8d00f75382";
    hash = "sha256-hzEFZjWoz2sspBtViddJ28d3rNFPgj/kXPadH0id5W0=";
  };

  skills = lib.attrNames skillDigests;
in
runCommand "${pname}-${version}" { } (
  lib.concatStringsSep "\n" (
    map (name: ''
      echo "${skillDigests.${name}}  ${src}/pstack/skills/${name}/SKILL.md" | sha256sum -c -
      install -Dm444 ${src}/pstack/skills/${name}/SKILL.md $out/share/claude-code/skills/${name}/SKILL.md
    '') skills
  )
)
