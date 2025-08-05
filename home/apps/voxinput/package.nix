{
  voxinput,
  fetchFromGitHub,
  pkg-config,
  libGL,
  libxkbcommon,
  wayland,
  xorg,
}:
voxinput.overrideAttrs (previousAttrs: rec {
  version = "b4258e60ede026d4de665999444b312a78649d34";

  src = fetchFromGitHub {
    owner = "richiejp";
    repo = "VoxInput";
    rev = "${version}";
    hash = "sha256-Uxl+qr4KEBAiIMbPlBq+1vvdjRDOsKOl+JOI1hjH4TE=";
  };

  vendorHash = "sha256-z7ais1eHoj15LzwsKbKl7qn9RIwxP1cd7WmoBs0Xzk0=";

  nativeBuildInputs = [
    pkg-config
  ]
  ++ previousAttrs.nativeBuildInputs;

  buildInputs = [
    libGL
    libxkbcommon
    wayland
    xorg.libX11.dev
    xorg.libXcursor
    xorg.libXi
    xorg.libXinerama
    xorg.libXrandr
    xorg.libXxf86vm
  ]
  ++ previousAttrs.buildInputs;

  postInstall = ''
    ${builtins.replaceStrings
      [ "--prefix PATH" ]
      [
        (
          "--set-default OPENAI_BASE_URL \"https://api.openai.com/v1\" "
          + "--set-default OPENAI_WS_BASE_URL \"wss://api.openai.com/v1/realtime\" "
          + "--run \"export OPENAI_API_KEY=\\\${OPENAI_API_KEY-\\$(secret-tool lookup service openai key api 2>/dev/null)}\" "
          + "--prefix PATH"
        )
      ]
      (previousAttrs.postInstall or "")
    }
  '';
})
