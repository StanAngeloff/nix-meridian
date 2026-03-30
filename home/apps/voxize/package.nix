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
  version = "main@{2026-03-30T13:00:00Z}";
  name = pname;

  src = fetchFromGitHub {
    owner = "Flemma-Dev";
    repo = "voxize";
    rev = builtins.replaceStrings [ "@" "{" "}" ":" ] [ "%40" "%7B" "%7D" "%3A" ] version;
    hash = "sha256-jPfi8LnRRX9aFtuC6HUw6JPeyD+3AE5dNHABI9+bNv8=";
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
