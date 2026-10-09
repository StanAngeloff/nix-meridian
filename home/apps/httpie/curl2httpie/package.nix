{
  writeShellApplication,
  name ? "curl2httpie",
  curlconverter,
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
    curlconverter
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
    # --type skips wl-copy's type guess, which waits on the GVfs metadata daemon; timeout stops a copy that never finishes.
    curlconverter --language httpie "$@" \
      | grep -viE '^\s+[[:punct:]]?(${builtins.concatStringsSep "|" excludeHeaders}):' \
      | perl -p -e 's/\s*\\\s*[\r\n]+\s*/ /' \
      | tee >(timeout 5 wl-copy --type text/plain)

    echo -ne "\033[0;32m"
    echo '✅ Copied.' 1>&2

    echo -ne "\033[0m"
  '';
}
