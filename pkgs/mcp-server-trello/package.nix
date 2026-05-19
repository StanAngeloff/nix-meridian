{
  lib,
  stdenv,
  fetchFromGitHub,
  bun,
  makeWrapper,
}:
let
  pname = "mcp-server-trello";
  version = "1.6.1";

  src = fetchFromGitHub {
    owner = "delorenj";
    repo = "mcp-server-trello";
    tag = "v${version}";
    hash = "sha256-JeqhwQUTbf4zzfoCNMtm6hM43cbFDiPqWW+jwRLabj8=";
  };

  bunDeps = stdenv.mkDerivation {
    name = "${pname}-${version}-bun-deps";
    inherit src;

    nativeBuildInputs = [ bun ];

    dontConfigure = true;
    dontFixup = true;

    buildPhase = ''
      export HOME=$TMPDIR
      bun install --frozen-lockfile
    '';

    installPhase = ''
      cp -rL node_modules $out
    '';

    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = "sha256-V/eGAkd8O1lD61JQnCg0ddFdJGzqP6p8Sl7wXdoW0Dw=";
  };
in
stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [
    bun
    makeWrapper
  ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR
    cp -r ${bunDeps} node_modules
    chmod -R u+w node_modules
    bun node_modules/typescript/bin/tsc
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/mcp-server-trello $out/bin
    cp -r build/* $out/lib/mcp-server-trello/
    cp -r node_modules $out/lib/mcp-server-trello/
    cp package.json $out/lib/mcp-server-trello/
    makeWrapper ${lib.getExe bun} $out/bin/mcp-server-trello \
      --add-flags "run $out/lib/mcp-server-trello/index.js"
    runHook postInstall
  '';

  meta = {
    description = "MCP server for Trello board management via Model Context Protocol";
    homepage = "https://github.com/delorenj/mcp-server-trello";
    license = lib.licenses.mit;
    mainProgram = "mcp-server-trello";
  };
}
