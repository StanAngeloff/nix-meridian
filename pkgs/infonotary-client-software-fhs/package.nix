{
  lib,
  stdenvNoCC,
  buildFHSEnv,
  infonotary-client-software,
  infonotary-idprime,
}:
# FHS wrapper for InfoNotary's signing apps (insigner = e-Doc Signer, scardmanager = Smart Card Manager).
# The underlying repackage is pkgs/infonotary-client-software.
#
# WHY THIS EXISTS: the proprietary binaries load their signing plugins —
# libqtcmsparser.so (the CMS signer, QCMSSigningComponent) and libqttsclient.so (the timestamp client) —
# by probing two HARD-CODED absolute directories and nothing else: /usr/lib64/infonotary then /usr/lib/infonotary
# (verified by strace; the binaries ignore $ORIGIN / applicationDirPath for this lookup). On NixOS neither exists,
# so signing fails with the dialog "A signing plugin is not available", even though the plugins ship in the store at
# ${infonotary-client-software}/lib/infonotary.
#
# buildFHSEnv runs each app inside a private bubblewrap mount namespace whose /usr is synthesised from targetPkgs.
# infonotary-client-software's $out/lib/infonotary therefore appears as /usr/lib/infonotary INSIDE that namespace,
# satisfying the hard-coded probe — while the host filesystem keeps no /usr/lib. This needs no binary patching
# (so it survives InfoNotary version bumps) and no system-side change: the whole fix stays in home.packages.
# The alternatives both touched the host — a /usr/lib symlink materialises FHS paths on a system that deliberately
# omits them, and a string-patched binary is fragile (NUL-padded, breaks on update).
let
  inherit (infonotary-client-software) version;

  # One FHS definition, instantiated per app. The synthesised /usr carries the apps' own binaries and libraries
  # (including lib/infonotary — the whole point); infonotary-idprime rides along so the IDPrime PKCS#11 module is
  # present in /usr/lib too (it is also reachable via the inner Qt wrapper's LD_LIBRARY_PATH). bubblewrap binds
  # /nix/store, $HOME (for ~/.pki/nssdb) and the session runtime dir (Wayland/X11/D-Bus socket) by default; the pcscd
  # socket dir /run/pcscd — how the card is reached — is NOT bound by default, so it is added explicitly (read-write,
  # as a socket connect needs it; -try tolerates pcscd being down).
  mkApp =
    app:
    buildFHSEnv {
      name = app;
      runScript = app;
      targetPkgs = pkgs: [
        infonotary-client-software
        infonotary-idprime
      ];
      extraBwrapArgs = [
        "--bind-try"
        "/run/pcscd"
        "/run/pcscd"
      ];
    };

  insigner = mkApp "insigner";
  scardmanager = mkApp "scardmanager";
in
stdenvNoCC.mkDerivation {
  pname = "infonotary-client-software-fhs";
  inherit version;

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    ln -s ${insigner}/bin/insigner $out/bin/insigner
    ln -s ${scardmanager}/bin/scardmanager $out/bin/scardmanager

    # Reuse the wrapped package's desktop entries / icons / file-manager actions, but repoint their Exec from the
    # non-FHS ${infonotary-client-software}/bin/<app> to the FHS launchers above, so a menu / file-manager launch
    # also enters the namespace (otherwise it would bypass the fix and still fail to find the signing plugins).
    cp -a ${infonotary-client-software}/share $out/share
    chmod -R u+w $out/share
    for f in $out/share/applications/*.desktop \
             $out/share/file-manager/actions/*.desktop \
             $out/share/kde4/services/ServiceMenus/*.desktop; do
      [ -e "$f" ] || continue
      substituteInPlace "$f" \
        --replace-quiet ${infonotary-client-software}/bin/insigner ${insigner}/bin/insigner \
        --replace-quiet ${infonotary-client-software}/bin/scardmanager ${scardmanager}/bin/scardmanager
    done

    runHook postInstall
  '';

  meta = infonotary-client-software.meta // {
    description = "InfoNotary e-Doc Signer + Smart Card Manager (FHS-wrapped so the hard-coded /usr/lib/infonotary plugin lookup resolves)";
    mainProgram = "insigner";
  };
}
