{
  config,
  lib,
  pkgs,
  ...
}:
# InfoNotary КЕП (qualified electronic signature) — all home-side wiring in one place.
# System-side stack (pcscd + OpenSC + the p11-kit module registration) lives in
# system/components/smartcard.nix; the CA chain is packaged in pkgs/infonotary-ca.
let
  # InfoNotary's official qualified eIDAS CA chain (pkgs/infonotary-ca), split into one clean PEM
  # per certificate. Firefox's Certificates.Install imports only the first certificate from a
  # bundle file, so every certificate in the chain must be installed as its own file. Reading the
  # directory is import-from-derivation: it builds the package at evaluation time.
  caPemDirectory = "${pkgs.infonotary-ca}/share/ca/pem";
  caPemFiles = map (name: "${caPemDirectory}/${name}") (
    builtins.attrNames (builtins.readDir caPemDirectory)
  );

  # The p11-kit proxy surfaces every PKCS#11 module registered under /etc/pkcs11/modules — where
  # system/components/smartcard.nix registers OpenSC (onepin). Firefox loads the proxy through its
  # policy; Chromium-family browsers load it from the per-user NSS database below. The proxy
  # library stays a garbage-collection root via smartcard.nix's systemPackages.
  p11KitProxy = "${pkgs.p11-kit}/lib/p11-kit-proxy.so";
in
{
  # InfoNotary e-Doc Signer + Smart Card Manager. FHS-wrapped so the apps' hard-coded /usr/lib/infonotary plugin
  # directory resolves at sign time — see pkgs/infonotary-client-software-fhs.
  #
  # StampIT Local Services — the Bulgarian Revenue Agency (НАП) local signing bridge that portal.nra.bg drives
  # over a localhost HTTP server. Same FHS technique so its hard-coded PKCS#11 module scan finds OpenSC — see
  # pkgs/stampit-local-services.
  home.packages = [
    pkgs.infonotary-client-software-fhs
    # StampIT's Swing dialogs in the user's configured UI font (IBM Plex Sans), enlarged for this HiDPI display.
    # The PIN prompt keeps a bytecode-hardcoded size, so it stays small — a known Java 8 limit; bump uiFontPt if
    # the rest is still too small.
    (pkgs.stampit-local-services.override {
      uiFont = config.nix-meridian.fonts.sansSerif.name;
      uiFontPackage = config.nix-meridian.fonts.sansSerif.package;
      uiFontPt = 28;
    })
  ];

  # ── Firefox: smart-card module + InfoNotary CA trust (fully declarative) ──────────────────────
  # These keys merge into home/apps/firefox/default.nix's policies through the home-manager module
  # system; the keys defined there (DisableTelemetry and friends) are disjoint from these.
  programs.firefox.policies = {
    # Expose the OpenSC / IDPrime token to Firefox via the p11-kit proxy security device.
    SecurityDevices.p11-kit-proxy = p11KitProxy;

    Certificates = {
      # Windows/macOS-only option with no effect on Linux; set explicitly to document intent —
      # Firefox trusts only the InfoNotary certificates installed below, not the operating
      # system's enterprise roots.
      ImportEnterpriseRoots = false;
      # One absolute /nix/store PEM per certificate in the chain.
      Install = caPemFiles;
    };
  };

  # ── Brave / Chromium family: smart-card module + InfoNotary CA trust via ~/.pki/nssdb ─────────
  # Chromium-family browsers cannot be pointed at a PKCS#11 module declaratively, and they read CA
  # trust only from their own per-user NSS database, so we register both with an idempotent
  # activation — InfoNotary's documented Linux method (modutil for the module, certutil for the
  # certificates). Home-manager runs activations under "set -eu -o pipefail", so every write is
  # tolerant of failure (warn, never abort "make switch") and read-only checks avoid pipelines.
  home.activation.infonotaryNssdb = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    nssdb="$HOME/.pki/nssdb"

    # Pre-create the legacy location so Brave (M146+) keeps using it instead of
    # ~/.local/share/pki/nssdb, and initialise an empty-password SQL database on first run.
    $DRY_RUN_CMD mkdir -p "$nssdb" \
      || echo "infonotary: could not create $nssdb; skipping Chromium-family smart-card setup" >&2
    if [ ! -e "$nssdb/cert9.db" ]; then
      $DRY_RUN_CMD ${pkgs.nssTools}/bin/certutil -N -d "sql:$nssdb" --empty-password \
        || echo "infonotary: could not initialise $nssdb" >&2
    fi

    # Work out what is missing before touching the database — this keeps the activation idempotent
    # and self-healing: a new p11-kit store path no longer matches and triggers a re-registration.
    # Capture the module list first, then match against a here-string: piping into "grep -q" under
    # "set -o pipefail" can spuriously fail when grep closes the pipe early.
    rawlist="$(${pkgs.nssTools}/bin/modutil -rawlist -dbdir "sql:$nssdb" 2>/dev/null || true)"
    proxyMissing=1
    if ${pkgs.gnugrep}/bin/grep -qF "${p11KitProxy}" <<< "$rawlist"; then
      proxyMissing=0
    fi

    anyCertMissing=0
    for cert in ${caPemDirectory}/*.pem; do
      nick="$(${pkgs.coreutils}/bin/basename "$cert" .pem)"
      ${pkgs.nssTools}/bin/certutil -L -d "sql:$nssdb" -n "$nick" >/dev/null 2>&1 \
        || anyCertMissing=1
    done

    if [ "$proxyMissing" -eq 0 ] && [ "$anyCertMissing" -eq 0 ]; then
      : # ~/.pki/nssdb already has the proxy and every InfoNotary certificate; nothing to do.
    elif ${pkgs.procps}/bin/pgrep 'brave|chrom' >/dev/null 2>&1; then
      echo "infonotary: ~/.pki/nssdb needs updating but a Chromium-family browser is running; close it and re-run 'make switch'." >&2
    else
      # (Re)register the proxy. delete-then-add with -force is self-healing across store-path
      # changes; the browser must be closed (checked above) or the SQL database can corrupt.
      if [ "$proxyMissing" -ne 0 ]; then
        $DRY_RUN_CMD ${pkgs.nssTools}/bin/modutil -force -dbdir "sql:$nssdb" -delete p11-kit-proxy >/dev/null 2>&1 || true
        $DRY_RUN_CMD ${pkgs.nssTools}/bin/modutil -force -dbdir "sql:$nssdb" -add p11-kit-proxy -libfile ${p11KitProxy} \
          || echo "infonotary: failed to register p11-kit-proxy in $nssdb" >&2
      fi

      # Import each InfoNotary certificate as a trusted issuer (CT,C,C = trusted CA for TLS server
      # and client authentication, for S/MIME, and for code signing).
      for cert in ${caPemDirectory}/*.pem; do
        nick="$(${pkgs.coreutils}/bin/basename "$cert" .pem)"
        if ! ${pkgs.nssTools}/bin/certutil -L -d "sql:$nssdb" -n "$nick" >/dev/null 2>&1; then
          $DRY_RUN_CMD ${pkgs.nssTools}/bin/certutil -A -d "sql:$nssdb" -n "$nick" -t "CT,C,C" -i "$cert" \
            || echo "infonotary: failed to import $nick into $nssdb" >&2
        fi
      done
    fi
  '';
}
