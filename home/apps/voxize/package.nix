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
    rev = "4f9101ae4a8e303c74bf1611b920178c250f3ceb";
    hash = "sha256-5jCnd0PIb6gp4degI9nppRD+AVRmS0O7j37suMqDJKE=";
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
