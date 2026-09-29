{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  ataraxy-sem,
  # Also install the three Claude Code launcher skills and name them in passthru.claudeCodeSkills,
  # which home/apps/claude-code/skills/default.nix links into ~/.claude/skills/.
  installSkills ? false,
  # Program Plannotator runs with the review URL (PLANNOTATOR_BROWSER); null keeps upstream's xdg-open.
  browserCommand ? null,
}:
let
  # Claude Code ingests these skills as prompts, verbatim, so each is pinned by content rather than by trust.
  # A changed file fails its fetch, so changing what Claude is told stays a deliberate act.
  # Update them only after reading the upstream diff, which update.sh shows before it asks.
  skillSha256 = {
    plannotator-review = "4bd390eca2ad8c13d1077005b5e3cb2d4f380b8a48c1eb51cbc6192430e3477d";
    plannotator-annotate = "be4666ee5d68cb3259cf3843f871d4a0455e3e6aa63c077c913e7e9b6f71b7f0";
    plannotator-last = "bbcd69c3d42470f2eae41942516e4a604524f6af7d35b6e12a0ef29d90687160";
  };
  skillNames = lib.attrNames skillSha256;

  # PLANNOTATOR_REMOTE: remote mode binds 0.0.0.0 with no authentication on the approve and feedback endpoints,
  #   and SSH_TTY or SSH_CONNECTION turn it on silently.
  # PLANNOTATOR_SHARE: share links carry the plan or diff to share.plannotator.ai; short links upload it.
  # PLANNOTATOR_JINA: annotating a URL would fetch it through r.jina.ai.
  # PLANNOTATOR_SEM_PATH: once set, the only sem Plannotator tries, never one from its data directory or PATH.
  # PLANNOTATOR_DATA_DIR: under ~/.claude, which the Claude Code bubble binds from the host, so bubbled sessions keep drafts.
  # vendor/: runtimes install there with code Nix never pinned (Call flow from the review UI, the agent terminal from
  #   the CLI); read-only makes both fail. The wrapper runs under bash -e, so a failed mkdir or chmod stops it before
  #   Plannotator starts with a writable vendor/.
  wrapperArgs = [
    # nixfmt: off
    "--set" "PLANNOTATOR_REMOTE" "0"
    "--set" "PLANNOTATOR_SHARE" "disabled"
    "--set-default" "PLANNOTATOR_JINA" "0"
    "--set" "PLANNOTATOR_SEM_PATH" (lib.getExe ataraxy-sem)
    "--run" ''export PLANNOTATOR_DATA_DIR="''${PLANNOTATOR_DATA_DIR:-$HOME/.claude/plannotator}"''
    "--run" ''mkdir -p "$PLANNOTATOR_DATA_DIR/vendor"''
    "--run" ''chmod 0555 "$PLANNOTATOR_DATA_DIR/vendor"''
    # nixfmt: on, as: shell-args
  ]
  ++ lib.optionals (browserCommand != null) [
    "--set-default"
    "PLANNOTATOR_BROWSER"
    browserCommand
  ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "plannotator";
  version = "0.27.22";

  # Upstream's release build (`bun build --compile`): a Bun runtime with the server and the review UI embedded.
  # update.sh verifies its SLSA provenance against upstream's release workflow before writing a bump.
  src = fetchurl {
    url = "https://github.com/backnotprop/plannotator/releases/download/v${finalAttrs.version}/plannotator-linux-x64";
    hash = "sha256-MNHRY5sdyy5XaVsrGKYeKeOYrQr0td8XmBoMoCS/w7M=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  # Bun finds the embedded application inside its own executable; stripping discards it and leaves the bare runtime.
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 $src $out/libexec/plannotator/plannotator
    makeWrapper $out/libexec/plannotator/plannotator $out/bin/plannotator ${lib.escapeShellArgs wrapperArgs}
  ''
  + lib.optionalString installSkills (
    lib.concatStrings (
      lib.mapAttrsToList (skillName: skillFile: ''
        install -Dm444 ${skillFile} $out/share/claude-code/skills/${skillName}/SKILL.md
      '') finalAttrs.passthru.skills
    )
  )
  + ''

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME="$(mktemp -d)"
    $out/bin/plannotator --version | grep -Fx "plannotator ${finalAttrs.version}"
    runHook postInstallCheck
  '';

  passthru = {
    skills = lib.mapAttrs (
      skillName: sha256:
      fetchurl {
        name = "${skillName}-SKILL.md";
        url = "https://raw.githubusercontent.com/backnotprop/plannotator/v${finalAttrs.version}/apps/skills/claude/${skillName}/SKILL.md";
        inherit sha256;
      }
    ) skillSha256;
    updateScript = ./update.sh;
  }
  // lib.optionalAttrs installSkills { claudeCodeSkills = skillNames; };

  meta = {
    description = "Browser-based review and annotation of code diffs, plans and files for coding agents";
    homepage = "https://github.com/backnotprop/plannotator";
    license = with lib.licenses; [
      mit
      asl20
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "plannotator";
  };
})
