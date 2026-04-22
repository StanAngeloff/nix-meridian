{
  lib,
  python313,
  fetchFromGitHub,
  # Build-time dependencies
  wrapGAppsHook4,
  gobject-introspection,
  # Runtime dependencies
  gtk4,
  libsecret,
  portaudio,
}:
let
  python = python313;
  runtimeDeps = [
    gtk4
    libsecret
    portaudio
  ];
in
python.pkgs.buildPythonApplication rec {
  pname = "voxize";
  version = "0.1.0-alpha";
  name = pname;

  src = fetchFromGitHub {
    owner = "Flemma-Dev";
    repo = "voxize";
    rev = "24d3342df18b4dae95e516e57e3e8071ee15382e";
    hash = "sha256-9i0HCaKQBomkAAqOb5j4oBK13kBIXFMY4+4ZTmeunjc=";
  };

  buildInputs = runtimeDeps;
  pyproject = true;

  nativeBuildInputs = [
    gobject-introspection
    wrapGAppsHook4
    python.pkgs.hatchling
    python.pkgs.hatch-vcs
  ];

  propagatedBuildInputs = with python.pkgs; [
    openai
    pygobject3
    sounddevice
    websockets
  ];

  dontWrapGApps = true;
  preFixup = ''
    makeWrapperArgs+=(
      "''${gappsWrapperArgs[@]}"
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeDeps}
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
