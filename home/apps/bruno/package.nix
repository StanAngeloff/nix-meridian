{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  makeWrapper,
  # dependencies
  alsa-lib,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gtk3,
  libGL,
  libdrm,
  libgbm,
  libnotify,
  libxkbcommon,
  nspr,
  nss,
  pango,
  udev,
  xorg,
}:
stdenv.mkDerivation rec {
  pname = "bruno";
  version = "2.3.0";
  # Use the official .deb release as it supports the 'Golden Edition'.
  # The package in nixpkgs is the re-packaged GitHub source which cannot be activated.
  src = fetchurl {
    url = "https://github.com/usebruno/bruno/releases/download/v${version}/bruno_${version}_amd64_linux.deb";
    sha256 = "sha256-Wv/8yUphE1VBxnSeD1pmmDGDklB33zQ7SWZPDHbvOcI=";
  };

  libPath = lib.makeLibraryPath [
    alsa-lib
    atk
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libGL
    libdrm
    libgbm
    libnotify
    libxkbcommon
    nspr
    nss
    pango
    udev
    xorg.libX11
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXi
    xorg.libXrandr
    xorg.libxcb
  ];

  nativeBuildInputs = [
    dpkg
    makeWrapper
  ];

  dontUnpack = true;
  dontBuild = true;
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall

    dpkg-deb -x $src $out
    mkdir -p $out/bin

    for file in $(find $out -type f \( -perm /0111 -o -name \*.so\* \) ); do
      patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" "$file" || true
      patchelf --set-rpath $libPath:$out/opt/Bruno $file || true
    done

    wrapProgram $out/opt/Bruno/bruno \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"

    ln -s $out/opt/Bruno/bruno $out/bin/bruno

    mv $out/usr/share $out/share
    rmdir $out/usr

    substituteInPlace $out/share/applications/bruno.desktop \
      --replace /opt/Bruno/bruno $out/opt/Bruno/bruno \
      --replace /usr/share/ $out/share/

    runHook postInstall
  '';

  meta = with lib; {
    description = "Git-integrated, fully offline, and open-source API client";
    homepage = "https://www.usebruno.com/";
    changelog = "https://www.usebruno.com/changelog";
    license = licenses.unfree;
    platforms = platforms.linux;
    mainProgram = "bruno";
  };
}
