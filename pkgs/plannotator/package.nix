{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  copyDesktopItems,
  makeDesktopItem,
  writeShellApplication,
  linkFarm,
  bubblewrap,
  bun,
  coreutils,
  # The overlay passes nixpkgs-unstable's Electron, the one the profile already carries for Proton Pass,
  # so the review window adds no second copy.
  electron,
  util-linux,
  ataraxy-sem,
  hunspellDictsChromium,
  # Also install the three Claude Code launcher skills and name them in passthru.claudeCodeSkills,
  # which home/apps/claude-code/skills/default.nix links into ~/.claude/skills/.
  installSkills ? false,
  # Program the review window runs with the URL of a link the user clicks (PLANNOTATOR_WINDOW_BROWSER);
  # null, or the program failing, copies the URL to the clipboard instead.
  browserCommand ? null,
  # The review page's spell-checking language as a BCP 47 tag ("en-GB"), from nixpkgs' Chromium dictionaries;
  # null leaves spell checking off.
  spellcheckLanguage ? null,
}:
let
  # Claude Code ingests these skills as prompts, verbatim, so each is pinned by content rather than by trust.
  # A changed file fails its fetch, so changing what Claude is told stays a deliberate act.
  # Update them only after reading the upstream diff, which update.sh shows before it asks.
  skillSha256 = {
    plannotator-review = "cd4631c42e8cf75ea80b829501bd78a2cf0a7e333e3d97500e6ac2cea8cbc8a5";
    plannotator-annotate = "d69c5b012cbeefcedd05970f5f55b5fba5b83d54d9c2a24fd8a3e1286f323b69";
    plannotator-last = "1a979daa6b39e86706b9e644ab7bd847f53373ecdfd6ec1d06d3d228727dd54d";
  };
  skillNames = lib.attrNames skillSha256;
  # The review window's icon: upstream's mascot, which the review page also serves as its favicon.
  # Pinned like the skills; update.sh rewrites it on a bump.
  iconSha256 = "4e99a26b076e421f654df83472c6186b62830d5db8fcd8e97d01947dffac28fd";

  # Under the file name Electron looks for in the profile (en-GB-10-1.bdic), which the window links it to.
  spellcheckDictionary =
    let
      dictionary =
        hunspellDictsChromium.${lib.toLower spellcheckLanguage}
        or (throw "plannotator: nixpkgs has no Chromium dictionary for ${spellcheckLanguage} (hunspellDictsChromium.${lib.toLower spellcheckLanguage})");
    in
    "${
      linkFarm "plannotator-spellcheck-dictionary" { ${dictionary.dictFileName} = dictionary; }
    }/${dictionary.dictFileName}";

  # The wrapper's last step: Plannotator, and every program it starts, runs in a network namespace that has only loopback.
  # See isolate.sh.
  isolate = writeShellApplication {
    name = "plannotator-isolate";
    text =
      lib.replaceStrings
        [ "@bwrap@" "@realpath@" ]
        [ (lib.getExe bubblewrap) (lib.getExe' coreutils "realpath") ]
        (builtins.readFile ./isolate.sh);
  };

  # Plannotator's browser command: the review in an Electron app of its own (./review-window), inside the namespace.
  # See review-window.sh. The pages it shows are this package's, so they come through the wrapper (PLANNOTATOR_WINDOW_PAGES).
  reviewWindow = writeShellApplication {
    name = "plannotator-review-window";
    text =
      lib.replaceStrings
        [
          "@bwrap@"
          "@setpriv@"
          "@flock@"
          "@mktemp@"
          "@electron@"
          "@appDirectory@"
        ]
        [
          (lib.getExe bubblewrap)
          (lib.getExe' util-linux "setpriv")
          (lib.getExe' util-linux "flock")
          (lib.getExe' coreutils "mktemp")
          (lib.getExe electron)
          "${builtins.path {
            path = ./review-window;
            name = "plannotator-review-window-app";
          }}"
        ]
        (builtins.readFile ./review-window.sh);
  };

  # Between isolate and Plannotator, inside the namespace: starts the review window beside the server. See prelaunch.sh.
  prelaunch = writeShellApplication {
    name = "plannotator-prelaunch";
    text =
      lib.replaceStrings
        [
          "@reviewWindow@"
          "@flock@"
          "@mktemp@"
        ]
        [
          (lib.getExe reviewWindow)
          (lib.getExe' util-linux "flock")
          (lib.getExe' coreutils "mktemp")
        ]
        (builtins.readFile ./prelaunch.sh);
  };

  # PLANNOTATOR_REMOTE: remote mode binds 0.0.0.0 with no authentication on the approve and feedback endpoints,
  #   and SSH_TTY or SSH_CONNECTION turn it on silently.
  # PLANNOTATOR_SHARE: share links carry the plan or diff to share.plannotator.ai; short links upload it.
  # PLANNOTATOR_AUTO_UPDATE: the opt-in self-updater (0.27.23 on) downloads and runs plannotator.ai/install.sh,
  #   which writes ~/.local/bin and agent integrations; set here, it beats config.json and locks the toggle in Settings.
  # PLANNOTATOR_UPDATE_CHECK: every review asks GitHub for a newer release, which the namespace never lets through,
  #   so the review page would report the check failing.
  # DO_NOT_TRACK: upstream's opt-out of its daily ping, which tells ping.plannotator.ai the version, the tool used
  #   (plan, review, annotate or last) and how many weeks Plannotator has been in use; the namespace stops it too.
  # PLANNOTATOR_AI: disabled takes the AI chat (Ask AI) off every page and the agent reviews off the review page:
  #   the servers refuse /api/ai/ and /api/agents/, and the pages hide both.
  #   The annotate page's agent terminal has no such switch; it needs a runtime in vendor/, below.
  # PLANNOTATOR_JINA: annotating a URL would fetch it through r.jina.ai.
  # PLANNOTATOR_GIT_REMOTE_CHECK: upstream's documented opt-out. The namespace has no route to a remote,
  #   so reviews compare against local refs instead of waiting on a `git ls-remote` that cannot succeed.
  # PLANNOTATOR_BROWSER: the review window. A browser command the caller sets instead still runs inside the namespace.
  # PLANNOTATOR_SEM_PATH: once set, the only sem Plannotator tries, never one from its data directory or PATH.
  # PLANNOTATOR_DATA_DIR: under ~/.claude, which the Claude Code bubble binds from the host, so bubbled sessions keep drafts.
  # vendor/: runtimes install there with code Nix never pinned (Call flow from the review UI, the agent terminal from the CLI);
  #   read-only makes both fail.
  #   The wrapper runs under bash -e, so a failed mkdir or chmod stops it before Plannotator starts with a writable vendor/.
  # PLANNOTATOR_WINDOW_BROWSER, PLANNOTATOR_WINDOW_SPELLCHECK_* and PLANNOTATOR_WINDOW_PAGES (set in installPhase):
  #   read by the review window, not by Plannotator (review-window/main.js).
  #   PLANNOTATOR_WINDOW_PRELAUNCH stays the caller's (prelaunch.sh).
  wrapperArgs = [
    # nixfmt: off
    "--set" "PLANNOTATOR_REMOTE" "0"
    "--set" "PLANNOTATOR_SHARE" "disabled"
    "--set" "PLANNOTATOR_AUTO_UPDATE" "0"
    "--set" "PLANNOTATOR_UPDATE_CHECK" "0"
    "--set" "DO_NOT_TRACK" "1"
    "--set" "PLANNOTATOR_AI" "disabled"
    "--set-default" "PLANNOTATOR_JINA" "0"
    "--set-default" "PLANNOTATOR_GIT_REMOTE_CHECK" "0"
    "--set-default" "PLANNOTATOR_BROWSER" (lib.getExe reviewWindow)
    "--set" "PLANNOTATOR_SEM_PATH" (lib.getExe ataraxy-sem)
    "--run" ''export PLANNOTATOR_DATA_DIR="''${PLANNOTATOR_DATA_DIR:-$HOME/.claude/plannotator}"''
    "--run" ''mkdir -p "$PLANNOTATOR_DATA_DIR/vendor"''
    "--run" ''chmod 0555 "$PLANNOTATOR_DATA_DIR/vendor"''
    # nixfmt: on, as: shell-args
  ]
  ++ lib.optionals (browserCommand != null) [
    "--set"
    "PLANNOTATOR_WINDOW_BROWSER"
    browserCommand
  ]
  ++ lib.optionals (spellcheckLanguage != null) [
    "--set"
    "PLANNOTATOR_WINDOW_SPELLCHECK_LANGUAGE"
    spellcheckLanguage
    "--set"
    "PLANNOTATOR_WINDOW_SPELLCHECK_DICTIONARY"
    spellcheckDictionary
  ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "plannotator";
  version = "0.28.48";

  # Upstream's release build (`bun build --compile`): a Bun runtime with the server and the review UI embedded.
  # update.sh verifies its SLSA provenance against upstream's release workflow before writing a bump.
  src = fetchurl {
    url = "https://github.com/backnotprop/plannotator/releases/download/v${finalAttrs.version}/plannotator-linux-x64";
    hash = "sha256-+gpB6OCgaa+E39CBygaJtChC5V4qckiAMBQPKaVaHbA=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    bun
    copyDesktopItems
    makeWrapper
  ];

  dontUnpack = true;
  dontConfigure = true;

  # The review window shows the plan and review pages itself (review-window/main.js), from copies of the files
  # the release embeds for them, which extract-bundle.js takes out of the binary's .bun section.
  buildPhase = ''
    runHook preBuild

    $OBJCOPY --output-target=binary --only-section=.bun $src bun-section
    bun ${./extract-bundle.js} bun-section pages

    runHook postBuild
  '';

  # Bun finds the embedded application inside its own executable; stripping discards it and leaves the bare runtime.
  dontStrip = true;

  # GNOME matches review windows to this entry by their Wayland app_id, which review-window/package.json sets.
  desktopItems = [
    (makeDesktopItem {
      name = "plannotator";
      desktopName = "Plannotator";
      comment = "Review window for Plannotator sessions";
      icon = "plannotator";
      startupWMClass = "plannotator";
      # Review windows open from Claude Code sessions only, so there is nothing to launch from the app grid.
      noDisplay = true;
      # An application entry needs a command; with SingleMainWindow GNOME offers no New Window that would run it.
      exec = "plannotator --version";
      singleMainWindow = true;
    })
  ];

  installPhase = ''
    runHook preInstall

    install -Dm755 $src $out/libexec/plannotator/plannotator
    mkdir -p $out/share/plannotator
    cp -r pages $out/share/plannotator/pages
    # The wrapper sets the environment above, then runs the binary through isolate, then prelaunch.
    makeWrapper ${lib.getExe isolate} $out/bin/plannotator \
      --add-flags "${lib.getExe prelaunch} $out/libexec/plannotator/plannotator" \
      --set PLANNOTATOR_WINDOW_PAGES $out/share/plannotator/pages ${lib.escapeShellArgs wrapperArgs}
    # Beside the binary, where tests/plannotator runs the launcher the way Plannotator does.
    ln -s ${lib.getExe reviewWindow} $out/libexec/plannotator/review-window
    install -Dm444 ${finalAttrs.passthru.icon} $out/share/icons/hicolor/256x256/apps/plannotator.png
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
    # Through the namespace, like every run: bwrap can create one inside the Nix build sandbox.
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
    icon = fetchurl {
      name = "plannotator.png";
      url = "https://raw.githubusercontent.com/backnotprop/plannotator/v${finalAttrs.version}/apps/marketing/public/favicon.png";
      sha256 = iconSha256;
    };
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
