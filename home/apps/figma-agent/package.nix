{
  lib,
  stdenv,
  fetchurl,
  # dependencies
  fontconfig,
  freetype,
}:
stdenv.mkDerivation rec {
  pname = "figma-agent";
  version = "0.3.2";

  src = fetchurl {
    url = "https://github.com/neetly/figma-agent-linux/releases/download/${version}/figma-agent-x86_64-unknown-linux-gnu";
    hash = "sha256-nDXgvq5Q/5KFkVeFMVhHXgDCcPX0DUig742XsR6DMC8=";
  };

  libPath = lib.makeLibraryPath [
    fontconfig
    freetype
  ];

  dontUnpack = true;
  dontBuild = true;
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin/
    cp $src $out/bin/${pname}
    chmod 0755 $out/bin/${pname}

    patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" "$out/bin/${pname}"
    patchelf --set-rpath $libPath "$out/bin/${pname}"

    runHook postInstall
  '';

  postInstall = ''
    mkdir -p $out/lib/systemd/user

    substitute ${./figma-agent.service} $out/lib/systemd/user/${pname}.service \
      --subst-var-by ${pname} $out/bin/${pname}
  '';

  meta = with lib; {
    description = "Figma Agent for Linux (a.k.a. Font Helper)";
    homepage = "https://github.com/neetly/figma-agent-linux";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "figma-agent";
  };
}
