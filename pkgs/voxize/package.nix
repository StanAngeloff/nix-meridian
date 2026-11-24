{
  lib,
  python313,
  fetchFromGitHub,
  fetchurl,
  # Build-time dependencies
  wrapGAppsHook4,
  gobject-introspection,
  # Runtime dependencies
  gtk4,
  libadwaita,
  libsecret,
  pipewire,
  portaudio,
  wl-clipboard,
  # Voxize Remote: adb for `voxize-remote setup-client`, ffmpeg for each dictation's Opus file (the systemd service has
  # no profile to find it in)
  android-tools,
  ffmpeg-headless,
  # Typography
  ibm-plex,
}:
let
  version = "0.4.2";
  python = python313;
  # Voxize Remote's Android client as the release signed it; `voxize-remote setup-client` installs it.
  remoteApk = fetchurl {
    url = "https://github.com/Flemma-Dev/voxize/releases/download/v${version}/voxize-remote-${version}.apk";
    hash = "sha256-3YQLWjLFy7YX3E8Ft3s1c+hYlBWtZDw+JqiSDGNGvJo=";
  };
  runtimeLibs = [
    gtk4
    libadwaita
    libsecret
    pipewire
    portaudio
  ];
  runtimeFonts = [
    ibm-plex
  ];
  runtimeDeps = runtimeLibs ++ runtimeFonts;
  pythonDeps = with python.pkgs; [
    openai
    pygobject3
    sounddevice
    textual
    websockets
  ];
in
python.pkgs.buildPythonApplication rec {
  pname = "voxize";
  inherit version;
  name = pname;

  src = fetchFromGitHub {
    owner = "Flemma-Dev";
    repo = "voxize";
    rev = "v${version}";
    hash = "sha256-x6ADE4crefsalE1inB4EJJ4NYlHpIW6rqnnbtcLqxnA=";
  };

  buildInputs = runtimeDeps;
  pyproject = true;

  nativeBuildInputs = [
    gobject-introspection
    wrapGAppsHook4
    python.pkgs.hatchling
  ];

  propagatedBuildInputs = pythonDeps;

  # Every entry point spawns `sys.executable -m voxize.backend` (and the meeting recorder `-m voxize.meeting`),
  # which bypasses the Nix Python wrapper's site.addsitedir calls. Export PYTHONPATH so subprocesses inherit it.
  # wl-copy is looked up on PATH: voxize-tui copies through it, and the window hands it a pending clipboard write on close.
  dontWrapGApps = true;
  preFixup =
    let
      pyPath = python.pkgs.makePythonPath (python.pkgs.requiredPythonModules pythonDeps);
    in
    ''
      makeWrapperArgs+=(
        "''${gappsWrapperArgs[@]}"
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibs}
        --set ALSA_PLUGIN_DIR ${pipewire}/lib/alsa-lib
        --prefix PYTHONPATH : "$out/${python.sitePackages}:${pyPath}"
        --prefix PATH : ${
          lib.makeBinPath [
            wl-clipboard
            android-tools
            ffmpeg-headless
          ]
        }
        --set-default VOXIZE_REMOTE_APK ${remoteApk}
      )
    '';

  passthru.remoteApk = remoteApk;

  # The systemd service runs voxize-remote with the wrapper's environment and little else: the keyring's typelib
  # (the server reads its pairings through it), the backend's PYTHONPATH, adb and ffmpeg must all come from the wrapper.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    (timeout 10 env -i HOME=$TMPDIR $out/bin/voxize-remote --control-socket $TMPDIR/control \
      serve --listen 127.0.0.1:0 2>$TMPDIR/serve.log || true)
    grep -q "control socket" $TMPDIR/serve.log || { cat $TMPDIR/serve.log; exit 1; }
    for wrapped in PYTHONPATH ${android-tools}/bin ${ffmpeg-headless.bin}/bin VOXIZE_REMOTE_APK; do
      grep -aq "$wrapped" $out/bin/voxize-remote || { echo "voxize-remote's wrapper lacks $wrapped"; exit 1; }
    done
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Voice-to-text for Linux (Wayland/GNOME): desktop overlay and terminal client";
    homepage = "http://flemma.dev/voxize";
    license = licenses.agpl3Only;
    platforms = platforms.linux;
    mainProgram = "voxize";
  };
}
