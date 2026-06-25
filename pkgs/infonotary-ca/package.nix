{
  stdenvNoCC,
  fetchurl,
  openssl,
}:
stdenvNoCC.mkDerivation {
  pname = "infonotary-ca";
  version = "eidas-2026";

  src = fetchurl {
    # Official InfoNotary qualified eIDAS certification chain: PKCS#12, empty password, public
    # certificates only (no private keys). Holds "InfoNotary TSP Root" plus the qualified
    # intermediate CAs. Bump version and hash when InfoNotary rotates the chain.
    url = "https://repository.infonotary.com/ra/InfoNotary_Qualified_eIDAS.p12";
    hash = "sha256-KIIWp9Vf3/oVvb9zg7v9oBSZCIGXI36hG/ukLMQWlQ8=";
  };

  dontUnpack = true;
  nativeBuildInputs = [ openssl ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/ca/pem"

    # Public certificates only; the .p12 has an empty password and carries no private keys.
    # openssl prints human-readable "Bag Attributes"/subject/issuer headers before each
    # certificate, so the raw output is not a clean PEM bundle.
    openssl pkcs12 -in "$src" -nokeys -passin pass: -out chain-raw.pem

    # Split on certificate boundaries. The first piece is openssl's leading header text (no
    # certificate at all); re-emitting every piece through `openssl x509` drops the headers and
    # lets us skip any piece that is not a real certificate.
    csplit -sz -f piece- -b "%03d" chain-raw.pem "/-----BEGIN CERTIFICATE-----/" "{*}"

    : > "$out/share/ca/InfoNotary-chain.pem"
    : > "$out/share/ca/der-base64.txt"
    i=0
    for piece in piece-*; do
      openssl x509 -in "$piece" -noout 2>/dev/null || continue # skip non-certificate pieces

      # Firefox's Certificates.Install imports only the first certificate from a bundle file, so
      # write one clean PEM per certificate; every CA is then listed and trusted on its own.
      cert="$(printf '%s/share/ca/pem/cert-%02d.pem' "$out" "$i")"
      openssl x509 -in "$piece" -out "$cert"
      cat "$cert" >> "$out/share/ca/InfoNotary-chain.pem"

      # Brave's CACertificates policy wants base64-encoded DER, one certificate per line.
      openssl x509 -in "$piece" -outform der | base64 -w0 >> "$out/share/ca/der-base64.txt"
      printf '\n' >> "$out/share/ca/der-base64.txt"

      i=$((i + 1))
    done

    runHook postInstall
  '';

  meta = {
    description = "InfoNotary qualified eIDAS CA chain (root + intermediates) from the official repository";
    homepage = "https://www.infonotary.com/";
  };
}
