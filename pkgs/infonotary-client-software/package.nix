{
  lib,
  stdenvNoCC,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  wrapQtAppsHook,
  qtbase,
  qtxmlpatterns,
  qtsvg,
  nss,
  nspr,
  pcsclite,
  openldap,
  infonotary-idprime,
}:
# InfoNotary's official Linux signing software — two Qt5 desktop apps shipped in one .deb:
#   • insigner       — e-Doc Signer: sign/verify PAdES, CAdES and XAdES documents
#   • scardmanager   — Smart Card Manager: manage the card, change PIN/AIN, unblock
#
# Both open the per-user NSS database (~/.pki/nssdb, wired by home/essentials/infonotary.nix) and load a card PKCS#11
# module via NSS. Their built-in module list names libIDPrimePKCS11.so (from infonotary-idprime) but not OpenSC,
# so the middleware is wired onto LD_LIBRARY_PATH below.
#
# Repackaged from InfoNotary's official apt repository as a fixed-output derivation (pinned hash from the repo's own
# Packages index → satisfies the project's official-sources rule). The Firefox / Chromium native-messaging hosts
# (SignZone in-browser signing) are deferred to a later phase.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "infonotary-client-software";
  version = "2.0.3.1216";

  src = fetchurl {
    url = "https://repository.infonotary.com/install/linux/DEBS24/pool/non-free/i/infonotary-client-software/infonotary-client-software_${finalAttrs.version}_amd64.deb";
    hash = "sha256-qbE6X2/Lczkw4ix8vi7j7sJ0ga2e2KUimSfvrESUPY8=";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    wrapQtAppsHook
  ];

  buildInputs = [
    qtbase # Qt5 Core/Gui/Widgets/Network/PrintSupport
    qtxmlpatterns # XAdES XML signing (scardmanager links libQt5XmlPatterns)
    qtsvg # Qt5 SVG image plugin for the app's vector icons
    nss # libnsscertstore → libnss3/libsmime3 (the ~/.pki/nssdb cert store)
    nspr # libnspr4
    pcsclite # libpcsclite
    openldap # libldap.so.2 — libnetworkclient's LDAP/CRL revocation fetching
    stdenv.cc.cc.lib # libstdc++ / libgcc_s for the C++ binaries
  ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x $src .
    runHook postUnpack
  '';
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib $out/share $out/etc/xdg

    # The two app binaries plus their ~20 bundled private libraries (the app's own crypto / CMS / timestamp-client
    # stack, including usr/lib/infonotary/*). autoPatchelfHook resolves the inter-library sonames within $out/lib
    # and the external deps from buildInputs.
    install -Dm755 usr/bin/insigner usr/bin/scardmanager -t $out/bin/
    cp -a usr/lib/. $out/lib/

    # Resources: desktop entries, icons/pixmaps, MIME types (.p7m/.p7s/.tsr)
    # and the file-manager right-click sign/verify/timestamp actions.
    cp -a usr/share/. $out/share/

    # Signing-scheme definitions (attached/detached/CAdES-T/long-term, TSA URL).
    # The apps read these from XDG_CONFIG_DIRS, wired in qtWrapperArgs below — no /etc dependency.
    cp -a etc/xdg/InfoNotary $out/etc/xdg/

    # SignZone browser integration is deferred: drop the native-messaging host launchers.
    rm -f $out/share/applications/insigner-host.desktop \
          $out/share/applications/scm-host.desktop

    # Rewrite the launchers/actions to the store paths:
    # /usr/bin/<app> → $out/bin/<app>,
    # the bare "Exec=insigner" → its absolute path,
    # and the absolute /usr/share/pixmaps icon references.
    for f in $out/share/applications/*.desktop \
             $out/share/file-manager/actions/*.desktop \
             $out/share/kde4/services/ServiceMenus/*.desktop; do
      [ -e "$f" ] || continue
      substituteInPlace "$f" \
        --replace-quiet /usr/bin/insigner $out/bin/insigner \
        --replace-quiet /usr/bin/scardmanager $out/bin/scardmanager \
        --replace-quiet "Exec=insigner" "Exec=$out/bin/insigner" \
        --replace-quiet /usr/share/pixmaps $out/share/pixmaps
    done

    runHook postInstall
  '';

  # Wrap both apps so they find: the IDPrime PKCS#11 module (bare dlopen("libIDPrimePKCS11.so")),
  # NSS's libsoftokn3.so (the app also probes hardcoded /usr paths — this is the bare-name fallback),
  # and the signing-scheme config under $out/etc/xdg.
  qtWrapperArgs = [
    "--prefix LD_LIBRARY_PATH : ${
      lib.makeLibraryPath [
        infonotary-idprime
        nss
      ]
    }"
    "--prefix XDG_CONFIG_DIRS : ${placeholder "out"}/etc/xdg"
    # GNOME doesn't expose a Qt-detectable session type, so default the platform to Wayland
    # (overridable at runtime, e.g. QT_QPA_PLATFORM=offscreen for debugging).
    "--set-default QT_QPA_PLATFORM wayland"
  ];

  meta = {
    description = "InfoNotary e-Doc Signer + Smart Card Manager (PAdES/CAdES/XAdES signing; card PIN/AIN management)";
    homepage = "https://www.infonotary.com/?p=technical-support";
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    mainProgram = "insigner";
    platforms = [ "x86_64-linux" ];
  };
})
