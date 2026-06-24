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
    rev = "1e9354ff58981242a0212e173130ed8b9b1a7134";
    hash = "sha256-kVnhekDXZT7i8m+WIgXDHhpKJntqk8fdMNeSy59UulM=";
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
