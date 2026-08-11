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
}:
let
  python = python313;
  runtimeDeps = [
    gtk4
    libadwaita
    libsecret
    pipewire
    portaudio
  ];
  pythonDeps = with python.pkgs; [
    openai
    pygobject3
    sounddevice
    websockets
  ];
in
python.pkgs.buildPythonApplication rec {
  pname = "voxize";
  version = "0.1.0-alpha";
  name = pname;

  src = fetchFromGitHub {
    owner = "Flemma-Dev";
    repo = "voxize";
    rev = "8b7108b2ef3cb0c2940e28eaed883984f534767e";
    hash = "sha256-tGyzCRzBeIdlZY5wyD7PilB0pJ39G+ZpfOUKOOPaqCs=";
  };

  buildInputs = runtimeDeps;
  pyproject = true;

  nativeBuildInputs = [
    gobject-introspection
    wrapGAppsHook4
    python.pkgs.hatchling
  ];

  propagatedBuildInputs = pythonDeps;

  # Voxize spawns subprocesses via sys.executable -m voxize.meeting, which bypasses the Nix
  # Python wrapper's site.addsitedir calls. Export PYTHONPATH so subprocesses inherit it.
  dontWrapGApps = true;
  preFixup =
    let
      pyPath = python.pkgs.makePythonPath (python.pkgs.requiredPythonModules pythonDeps);
    in
    ''
      makeWrapperArgs+=(
        "''${gappsWrapperArgs[@]}"
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeDeps}
        --set ALSA_PLUGIN_DIR ${pipewire}/lib/alsa-lib
        --prefix PYTHONPATH : "$out/${python.sitePackages}:${pyPath}"
      )
    '';

  meta = with lib; {
    description = "Voice-to-text tool for Linux (Wayland/GNOME)";
    homepage = "http://flemma.dev/voxize";
    license = licenses.agpl3Only;
    platforms = platforms.linux;
    mainProgram = "voxize";
  };
}
