{
  lib,
  stdenvNoCC,
  fetchurl,
}:
stdenvNoCC.mkDerivation rec {
  pname = "n8n-cli";
  version = "0.7.1";

  src = fetchurl {
    url = "https://github.com/edenreich/n8n-cli/releases/download/v${version}/n8n_linux_amd64";
    hash = "sha256-vr+ffepj/0MPM76QeSeKAXvABUtSz0h1HI4jw86Xk0I=";
  };

  dontUnpack = true;

  installPhase = ''
    install -Dm755 $src $out/bin/n8n
  '';

  meta = with lib; {
    description = "CLI tool for managing n8n workflows";
    homepage = "https://github.com/edenreich/n8n-cli";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "n8n";
  };
}
