{
  lib,
  python313,
  fetchFromGitHub,
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
  # Typography
  ibm-plex,
}:
let
  python = python313;
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
  version = "0.3.2";
  name = pname;

  src = fetchFromGitHub {
    owner = "Flemma-Dev";
    repo = "voxize";
    rev = "v${version}";
    hash = "sha256-WkX04sOi5Eq1STSJh1bIgYg4fiz3zortaeCbveBFIko=";
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
        --prefix PATH : ${lib.makeBinPath [ wl-clipboard ]}
      )
    '';

  meta = with lib; {
    description = "Voice-to-text for Linux (Wayland/GNOME): desktop overlay and terminal client";
    homepage = "http://flemma.dev/voxize";
    license = licenses.agpl3Only;
    platforms = platforms.linux;
    mainProgram = "voxize";
  };
}
