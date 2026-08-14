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
  # Typography
  source-serif,
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
    source-serif
    ibm-plex
  ];
  runtimeDeps = runtimeLibs ++ runtimeFonts;
  pythonDeps = with python.pkgs; [
    openai
    pygobject3
    sounddevice
    websockets
  ];
in
python.pkgs.buildPythonApplication rec {
  pname = "voxize";
  version = "0.1.0";
  name = pname;

  src = fetchFromGitHub {
    owner = "Flemma-Dev";
    repo = "voxize";
    rev = "6c3942d9eb92288b8d4a8a5cfc1be4a4c9967d7e";
    hash = "sha256-SwBHT63weQ4hy0y1TsH8fy8SMz3dqPi3C1ZmYbpXMOU=";
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
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibs}
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
