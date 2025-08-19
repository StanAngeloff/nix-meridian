{
  writeShellApplication,
  name ? "curl2httpie",
  curlconverterVersion ? "4.12",
  pnpm,
  coreutils,
  gnugrep,
  perl,
  wl-clipboard,
}:
let
  excludeHeaders = [
    "Accept-Encoding"
    "Accept-Language"
    "Cache-Control"
    "Connection"
    "DNT"
    "Expires"
    "Pragma"
    "Priority"
    "Sec-\\w+(-\\w+)*"
    "TE"
    "User-Agent"
  ];
in
writeShellApplication {
  inherit name;

  runtimeInputs = [
    pnpm
    coreutils
    gnugrep
    perl
    wl-clipboard
  ];

  text = ''
    # If the first argument is `curl`, shift it off.
    if [[ "$1" == "curl" ]]; then
      shift
    fi

    echo -ne "👉 \033[0;36m"
    pnpm --silent --package=curlconverter@${curlconverterVersion} dlx -- \
        curlconverter --language httpie "$@" \
      | grep -viE '^\s+[[:punct:]]?(${builtins.concatStringsSep "|" excludeHeaders}):' \
      | perl -p -e 's/\s*\\\s*[\r\n]+\s*/ /' \
      | tee >(wl-copy)

    echo -ne "\033[0;32m"
    echo '✅ Copied.' 1>&2

    echo -ne "\033[0m"
  '';
}
