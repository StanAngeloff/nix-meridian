{
  lib,
  stdenvNoCC,
  fetchurl,
  dpkg,
  unzip,
  zip,
  makeWrapper,
  wrapGAppsHook3,
  zulu25,
  gtk3,
  gsettings-desktop-schemas,
  libappindicator-gtk3,
  pcsclite,
  infonotary-idprime,
}:
# InfoNotary e-Doc Signer — InfoNotary's official Linux signing software. It signs, verifies and timestamps PAdES,
# CAdES and XAdES documents with the qualified smart card, and its --smc mode is the Smart Card Manager
# (PIN change and unblock, certificates, keys). One JavaFX 25 application shipped as a single jar.
#
# The .deb wraps that jar in a jpackage bundle with a private Java runtime under /opt. Only the jar is kept, and it runs
# on nixpkgs' Azul Zulu JDK with JavaFX: a prebuilt, already patched runtime that includes WebKit (javafx.web), which
# the app needs because every alert dialog renders its icon through a WebView. The JavaFX classes and native libraries
# bundled inside the jar are shadowed by the runtime's own JavaFX modules, so they are never loaded.
#
# Resources inside the jar are patched — data only, no bytecode (the jar is unsigned):
#   • docsign_config_l.ini — the PKCS#11 driver list. The app seeds ~/.InfoNotary/docsign_config_l.ini from it on first
#     start and on "reset settings", and the vendor default names /usr/lib/libIDPrimePKCS11.so. It now names
#     infonotary-idprime's copy. The same patched file is installed under share/ so home/essentials/infonotary.nix can
#     link it into place; the app migrates that file only when the jar's config_version is newer, and the two match.
#   • application.properties — sentry.dsn is blanked, which disables the Sentry SDK. Otherwise the app sends crash
#     reports and 100% of its performance traces to sentry.io, and this file is the DSN's only source.
#   • light.css and dark.css — the font family becomes the generic sans-serif, which JavaFX resolves through fontconfig,
#     so the UI follows the system font. The stylesheets name "Arial" and "Liberation Sans", and on Linux the app
#     rewrites "Arial" to "Liberation Sans" at startup and loads its own copy of that font from the jar.
#     The "update available" dialog and the HTML in the About dialog name Liberation Sans in code and keep it.
#
# Every start checks https://repository.infonotary.com/docSignLin/version.properties. On Linux a newer version only
# raises an "update available" dialog (nothing is downloaded or executed), so the vendor's UpdateLauncher entry point
# is kept: that dialog is the cue to bump this pin, because InfoNotary removes superseded .debs from the repository.
let
  jdk = zulu25.override { enableJavaFX = true; };

  jar = "share/java/infonotary-client-software.jar";
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "infonotary-client-software";
  version = "3.0.29";

  src = fetchurl {
    url = "https://repository.infonotary.com/install/linux/DEBS24/pool/non-free/i/infonotary-client-software/infonotary-client-software_${finalAttrs.version}_all.deb";
    hash = "sha256-Um5ZhMiUPzqcS57OgfCzTloYqs0yh4QLRwMCwx8PWww=";
  };

  nativeBuildInputs = [
    dpkg
    unzip
    zip
    makeWrapper
    wrapGAppsHook3
  ];

  # GTK's GSettings schemas for JavaFX's GTK file chooser, collected into the wrapper by wrapGAppsHook3.
  buildInputs = [
    gtk3
    gsettings-desktop-schemas
  ];

  # The wrapper is built by hand in postFixup, around java rather than around a binary in $out.
  dontWrapGApps = true;

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x $src .
    runHook postUnpack
  '';
  sourceRoot = ".";

  buildPhase = ''
    runHook preBuild

    vendorJar="opt/InfoNotary e-Doc Signer/lib/app/DocSigner-linux_obfuscated.jar"
    patchedResources="docsign_config_l.ini application.properties light.css dark.css"
    mkdir resources
    unzip -q "$vendorJar" $patchedResources -d resources

    substituteInPlace resources/docsign_config_l.ini \
      --replace-fail /usr/lib/libIDPrimePKCS11.so ${infonotary-idprime}/lib/libIDPrimePKCS11.so

    # The DSN value changes between releases, so match the key; the grep fails the build if the key ever moves.
    sed -i -E 's|^sentry\.dsn[[:space:]]*=.*$|sentry.dsn =|' resources/application.properties
    grep -qx 'sentry.dsn =' resources/application.properties

    substituteInPlace resources/light.css resources/dark.css \
      --replace-fail '"Arial"' sans-serif \
      --replace-fail '"Liberation Sans"' sans-serif

    cp "$vendorJar" infonotary-client-software.jar
    chmod u+w infonotary-client-software.jar
    (
      cd resources
      touch -d @$SOURCE_DATE_EPOCH $patchedResources
      zip -q -X ../infonotary-client-software.jar $patchedResources
    )

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm644 infonotary-client-software.jar $out/${jar}
    install -Dm644 resources/docsign_config_l.ini $out/share/infonotary-client-software/docsign_config_l.ini

    # Application icon (named, instead of the vendor's absolute /opt path) and the .p7m/.p7s/.tsr MIME types with
    # their icons.
    install -Dm644 "opt/InfoNotary e-Doc Signer/lib/InfoNotary_e-Doc_Signer.svg" \
      $out/share/icons/hicolor/scalable/apps/infonotary-e-doc-signer.svg
    cp -r usr/share/icons/hicolor/. $out/share/icons/hicolor/
    install -Dm644 -t $out/share/mime/packages usr/share/mime/packages/*.xml

    # Desktop entries and Nautilus "Scripts" actions, repointed from the jpackage launcher to the wrappers below.
    # Nautilus reads scripts only from ~/.local/share/nautilus/scripts; home/essentials/infonotary.nix links them.
    install -Dm644 -t $out/share/applications usr/share/applications/*.desktop
    substituteInPlace $out/share/applications/infonotary-e-doc-signer-InfoNotary_e-Doc_Signer.desktop \
      --replace-fail '"/opt/InfoNotary e-Doc Signer/bin/InfoNotary e-Doc Signer"' $out/bin/infonotary-docsigner \
      --replace-fail '/opt/InfoNotary e-Doc Signer/lib/InfoNotary_e-Doc_Signer.svg' infonotary-e-doc-signer
    substituteInPlace $out/share/applications/infonotary-smart-card-manager.desktop \
      --replace-fail '"/opt/InfoNotary e-Doc Signer/bin/InfoNotary e-Doc Signer" --smc' $out/bin/infonotary-smc \
      --replace-fail '/opt/InfoNotary e-Doc Signer/lib/InfoNotary_e-Doc_Signer.svg' infonotary-e-doc-signer

    install -Dm755 -t $out/share/nautilus/scripts usr/share/nautilus/scripts/*
    for script in $out/share/nautilus/scripts/*; do
      substituteInPlace "$script" \
        --replace-fail '"/opt/InfoNotary e-Doc Signer/bin/InfoNotary e-Doc Signer"' $out/bin/infonotary-docsigner
    done

    runHook postInstall
  '';

  # In postFixup because wrapGAppsHook3 collects gappsWrapperArgs during preFixup.
  #   • LD_LIBRARY_PATH — libraries the jar loads by name through JNA: libpcsclite (the PC/SC card stack), and GTK 3
  #     plus the legacy libappindicator3 for the tray icon, which is the only way back to a window closed to the tray.
  #   • sun.security.smartcardio.library — javax.smartcardio (the reader list) otherwise probes FHS paths only.
  #   • --enable-native-access — JNA (in the jar) and JavaFX load native code, which Java 24+ restricts.
  postFixup = ''
    makeWrapper ${jdk}/bin/java $out/bin/infonotary-docsigner \
      "''${gappsWrapperArgs[@]}" \
      --prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath [
          gtk3
          libappindicator-gtk3
          pcsclite
        ]
      } \
      --add-flags "-Dsun.security.smartcardio.library=${lib.getLib pcsclite}/lib/libpcsclite.so.1" \
      --add-flags "--enable-native-access=ALL-UNNAMED,javafx.graphics,javafx.web" \
      --add-flags "-jar $out/${jar}"

    # The jar picks the Smart Card Manager only when --smc is the first argument.
    makeWrapper $out/bin/infonotary-docsigner $out/bin/infonotary-smc --add-flags --smc
  '';

  meta = {
    description = "InfoNotary e-Doc Signer and Smart Card Manager (PAdES/CAdES/XAdES signing, verification, timestamps)";
    homepage = "https://www.infonotary.com/?p=technical-support";
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    mainProgram = "infonotary-docsigner";
    platforms = [ "x86_64-linux" ];
  };
})
