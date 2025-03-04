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

    echo -e "\033[0;36m"
    pnpm --silent dlx curlconverter@${curlconverterVersion} --language httpie "$@" \
      | grep -vE '^\s+"?(Connection|User-Agent|Sec-\w+(-\w+)*|TE|DNT|Expires|Pragma|Cache-Control|Accept-Language|Accept-Encoding):' \
      | perl -p -e 's/\s*\\\s*[\r\n]+\s*/ /' \
      | tee >(wl-copy)

    echo -e "\033[0;32m"
    echo 'Copied.' 1>&2

    echo -e "\033[0m"
  '';
}
