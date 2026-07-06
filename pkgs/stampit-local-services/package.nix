{
  lib,
  stdenvNoCC,
  fetchurl,
  buildFHSEnv,
  makeDesktopItem,
  copyDesktopItems,
  writeShellScript,
  makeFontsConf,
  temurin-jre-bin-8,
  opensc,
  pcsclite,
  fontconfig,
  freetype,
  dejavu_fonts,
  unzip,
  # UI font family + point size for the Swing dialogs. Overridden from home/essentials/infonotary.nix with the
  # user's configured sans-serif (config.nix-meridian.fonts.sansSerif); the defaults keep this package usable
  # standalone. uiFontPackage is added to the FHS fontconfig so the JVM can actually resolve uiFont.
  uiFont ? "SansSerif",
  uiFontPackage ? null,
  uiFontPt ? 24,
}:
# StampIT Local Services — the Bulgarian Revenue Agency (НАП) local signing bridge.
#
# portal.nra.bg performs client-side signing by handing the browser a Java Web Start descriptor
# (stampitls.jnlp) whose app — "StampIT Local Services Manager", vendor Information Services JSC — starts a
# small HTTP server on 127.0.0.1 (it tries ports 8090 → 23125 → 53951; endpoints /version and /sign). The
# portal's JavaScript POSTs the to-be-signed data to that local port, the app signs it with the card, and
# returns the signature. That local server IS the whole "run the .jnlp so the browser can sign" mechanism.
#
# We deliberately do NOT use Java Web Start. On Linux the app has zero javax.jnlp usage and ships no native
# libraries, so the JNLP is pure bootstrap: choose Java 8, download two jars, run a main class — all of which
# we do here directly. That removes any need for IcedTea-Web / OpenWebStart.
#
# The app has two hard requirements, and how each is satisfied on NixOS:
#
#   1. Java 8, specifically. The signer builds its PKCS#11 provider with `new SunPKCS11(configPath)`, the
#      constructor Java 9 removed (in favour of Provider.configure). Hence temurin-jre-bin-8 — and hence the
#      JNLP's own `j2se version="1.8*"`.
#
#   2. Its PKCS#11 module on a hardcoded FHS path. bg.nra.inetdec.utils.t scans a fixed directory list
#      (/usr/lib, /usr/lib/pkcs11, /usr/lib64, /usr/lib64/pkcs11, /usr/local/lib, …) for a module named exactly
#      `opensc-pkcs11.so` (OpenSC — the same module the browsers already use for this IDPrime card), with no
#      environment or config override. None of those paths exist on NixOS. buildFHSEnv runs the JVM inside a
#      bubblewrap namespace whose /usr is synthesised from targetPkgs, so opensc's lib/pkcs11/opensc-pkcs11.so
#      appears at /usr/lib/pkcs11/opensc-pkcs11.so and the scan succeeds — no host /usr, no binary patching.
#      This is the same technique as pkgs/infonotary-client-software-fhs.
#
# The jars are pinned fixed-output derivations fetched from the portal (the official source). The JNLP marks
# itself <update check="always"/>; bypassing Web Start means we ignore that, so a portal-side version bump
# surfaces here as a hash mismatch — re-fetch the two URLs and update the hashes (identical maintenance to the
# infonotary-client-software .deb pin).
let
  lsManagerJar = fetchurl {
    url = "https://portal.nra.bg/ls/LSManager.jar";
    hash = "sha256-KBJCOiwokZkSmV4I/BKKfki1/Jd/asusB0Edm/DoA54=";
  };
  signerServiceJar = fetchurl {
    url = "https://portal.nra.bg/ls/SignerService.jar";
    hash = "sha256-tcZ3oxJ/YxE0TLaxwxpa/LtSEXE9Ms+QQpSwPENDHu4=";
  };

  # Fonts the JVM can see inside the FHS: DejaVu (broad Cyrillic coverage for the Bulgarian UI, and the fallback
  # when no UI font is configured) plus the caller's configured UI font, if any. Pointing FONTCONFIG_FILE at this
  # self-contained fonts.conf means Swing resolves them regardless of what the synthesised FHS /etc carries.
  fontsConf = makeFontsConf {
    fontDirectories = [ dejavu_fonts ] ++ lib.optional (uiFontPackage != null) uiFontPackage;
  };

  # HiDPI workaround. Java 8 has no display scaling, and the app forces the GTK system look-and-feel whose font
  # GNOME dictates globally (XSETTINGS) and cannot be overridden per-process — so on a 4K panel the UI is
  # microscopic. We instead force Swing's Metal look-and-feel (via swing.systemlaf, which the
  # getSystemLookAndFeelClassName call the app makes honours) because Metal's fonts ARE settable per-process, then
  # set them to uiFont at uiFontPt. NOTE: a few dialog labels (notably the PIN prompt) hardcode their own font
  # size in bytecode — new Font("Tahoma", …, 12) — and cannot be scaled this way; that is Java 8's ceiling.

  # Runs INSIDE the FHS namespace. SignerService.jar carries a META-INF/services LocalService provider that
  # LSManager discovers off the classpath, so both jars go on -cp.
  #   • sun.security.smartcardio.library — Temurin's PC/SC layer probes FHS paths that do not exist here for
  #     libpcsclite; pinning it to the store copy makes the app's javax.smartcardio card scan succeed, so it
  #     auto-selects OpenSC instead of demanding a manual "PKCS11 библиотека…" pick.
  #   • swing.* — force Metal and enlarge its fonts (see uiFontPt) for a readable UI on HiDPI.
  launcher = writeShellScript "stampit-ls" ''
    export FONTCONFIG_FILE=${fontsConf}
    exec ${temurin-jre-bin-8}/bin/java \
      -Dsun.security.smartcardio.library=${lib.getLib pcsclite}/lib/libpcsclite.so.1 \
      -Dswing.systemlaf=javax.swing.plaf.metal.MetalLookAndFeel \
      -Dswing.useSystemFontSettings=false \
      "-Dswing.plaf.metal.controlFont=${uiFont}-${toString uiFontPt}" \
      "-Dswing.plaf.metal.userFont=${uiFont}-${toString uiFontPt}" \
      "-Dswing.plaf.metal.systemFont=${uiFont}-${toString uiFontPt}" \
      "-Dswing.plaf.metal.smallFont=${uiFont}-${toString (uiFontPt - 4)}" \
      -cp ${lsManagerJar}:${signerServiceJar} \
      net.isbg.ls.lsmanager.AppGUI "$@"
  '';

  fhs = buildFHSEnv {
    name = "stampit-ls";
    runScript = "${launcher}";

    # opensc → /usr/lib(/pkcs11)/opensc-pkcs11.so for the module scan; pcsclite so the app's javax.smartcardio
    # card scan can load libpcsclite (also pinned explicitly via -Dsun.security.smartcardio.library above);
    # fontconfig + freetype so the JVM can dlopen libfontconfig / libfreetype for text rendering.
    targetPkgs = pkgs: [
      opensc
      pcsclite
      fontconfig
      freetype
    ];

    # /run/pcscd (the pcscd socket dir — how the card is reached) is not bound by default; -try tolerates pcscd
    # being down. The X11 socket dir is bound so Java's AWT reaches XWayland under GNOME.
    extraBwrapArgs = [
      "--bind-try"
      "/run/pcscd"
      "/run/pcscd"
      "--ro-bind-try"
      "/tmp/.X11-unix"
      "/tmp/.X11-unix"
    ];
  };

  desktopItem = makeDesktopItem {
    name = "stampit-local-services";
    desktopName = "НАП — StampIT Local Services";
    genericName = "Revenue Agency signing bridge";
    comment = "Local signing service for the Bulgarian Revenue Agency portal (portal.nra.bg)";
    exec = "${fhs}/bin/stampit-ls";
    icon = "stampit-local-services";
    terminal = false;
    startupNotify = false;
    categories = [
      "Office"
      "Security"
    ];
    keywords = [
      "НАП"
      "NRA"
      "StampIT"
      "sign"
      "подпис"
      "revenue"
    ];
  };
in
stdenvNoCC.mkDerivation {
  pname = "stampit-local-services";
  version = "0.9.9"; # LSManager.jar Implementation-Version (SignerService.jar is 0.30).

  dontUnpack = true;

  nativeBuildInputs = [
    copyDesktopItems
    unzip
  ];
  desktopItems = [ desktopItem ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    ln -s ${fhs}/bin/stampit-ls $out/bin/stampit-ls

    # Reuse the app's own bundled icon (img/icon.png inside LSManager.jar); skip quietly if it is ever absent.
    if unzip -p ${lsManagerJar} img/icon.png > icon.png 2>/dev/null && [ -s icon.png ]; then
      install -Dm644 icon.png $out/share/pixmaps/stampit-local-services.png
    fi

    runHook postInstall
  '';

  meta = {
    description = "StampIT Local Services — Bulgarian Revenue Agency (НАП) local signing bridge for portal.nra.bg, FHS-wrapped so its hardcoded PKCS#11 scan finds OpenSC on NixOS";
    homepage = "https://portal.nra.bg/";
    license = lib.licenses.unfree; # Proprietary — Information Services JSC (is-bg.net).
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "stampit-ls";
  };
}
