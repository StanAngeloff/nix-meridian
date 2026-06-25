{
  lib,
  stdenvNoCC,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  pcsclite,
  openssl,
}:
# InfoNotary ships Thales/Gemalto's SafeNet Authentication Client (SAC) "core" as the IDPrime smart-card middleware.
# It provides libIDPrimePKCS11.so — the PKCS#11 module the InfoNotary e-Doc Signer / Smart Card Manager expect for
# IDPrime cards (their built-in module list names libIDPrimePKCS11.so but not OpenSC, so OpenSC alone may not be
# accepted there even though it drives the card fine in the browsers).
#
# libeToken.so links libpcsclite directly, so the stack reaches the card through pcscd on its own. The SACSrv daemon
# and its systemd unit are intentionally NOT packaged: they drive eTokenDrive/HID mass-storage
# and token-change notifications, not PKCS#11 card access.
#
# Repackaged from InfoNotary's official apt repository as a fixed-output derivation
# (pinned hash from the repo's own Packages index → satisfies the project's official-sources rule).
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "infonotary-idprime";
  version = "10.9.4723";

  src = fetchurl {
    url = "https://repository.infonotary.com/install/linux/DEBS24/pool/non-free/s/safenetauthenticationclient/safenetauthenticationclient-core_${finalAttrs.version}_amd64.deb";
    hash = "sha256-crHtpGaQBRzyebV6oj3HcbtvHym4EKhwUafVqeP5LsE=";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
  ];

  # libeToken.so → libpcsclite.so.1 (PC/SC, the card path) and libcrypto.so.3 (OpenSSL 3);
  # the remaining inter-library dependencies resolve within $out/lib via each library's $ORIGIN runpath.
  buildInputs = [
    pcsclite
    openssl
  ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x $src .
    runHook postUnpack
  '';
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    # libIDPrimePKCS11.so is a thin entry point that dlopens its token engines (libIDPrime*Engine, libeToken, …)
    # from $ORIGIN, so every SAC library must stay co-located in one directory.
    mkdir -p $out/lib
    cp -a usr/lib/. $out/lib/
    runHook postInstall
  '';

  meta = {
    description = "InfoNotary IDPrime smart-card middleware — SafeNet Authentication Client core (libIDPrimePKCS11.so)";
    homepage = "https://www.infonotary.com/?p=technical-support";
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
  };
})
