{
  lib,
  stdenv,
  fetchFromGitHub,
  nodejs_24,
  makeWrapper,
  autoPatchelfHook,
  util-linux,
  cacert,
}:
let
  pname = "slopsift";
  version = "0.11.0";

  src = fetchFromGitHub {
    owner = "NikhilVerma";
    repo = "writinglint";
    tag = "slopsift@${version}";
    hash = "sha256-2PLBfAZO8ftMGtmiFDdwyo3Gw2X3pHmtTNGVtRxYCSQ=";
  };

  nodejs = nodejs_24;

  # Claude Code ingests this skill as a prompt, verbatim, so it is pinned by content rather than by trust.
  # The source hash covers the file already, but it covers everything else too: without a separate pin,
  # a routine bump for a bug fix would carry any rewritten instructions along with it, silently.
  # postInstall checks this digest and fails the build instead, so changing what Claude is told stays a deliberate act.
  # Update it only after reading the upstream diff.
  skillSha256 = "9877757bb95743b19894b750ac20d314ee0343a531b522f180216c8bd62ee8f0";

  # Fixed-output derivation: npm install produces the full node_modules tree.
  # The output hash pins the exact closure; a version bump requires updating it.
  npmDeps = stdenv.mkDerivation {
    name = "${pname}-${version}-npm-deps";

    dontUnpack = true;
    nativeBuildInputs = [ nodejs ];

    buildPhase = ''
      export HOME=$TMPDIR
      export npm_config_cache=$TMPDIR/npm-cache
      export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
      export NODE_EXTRA_CA_CERTS=${cacert}/etc/ssl/certs/ca-bundle.crt

      cat > package.json <<'PACKAGE'
      {"name":"slopsift-nix","private":true,"dependencies":{"slopsift":"${version}"}}
      PACKAGE

      npm install --ignore-scripts --no-audit --no-fund
    '';

    installPhase = ''
      cp -rL node_modules $out
    '';

    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = "sha256-DrlKW/npUaFAG/LmpSOWRjVs4EGRDfmPKnlK3K7KbrY=";
  };
in
stdenv.mkDerivation {
  inherit pname version src;

  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  # onnxruntime-node ships prebuilt linux/x64 binaries that link libstdc++.
  buildInputs = [
    stdenv.cc.cc.lib
  ];

  installPhase = ''
    runHook preInstall

    # Library tree: the npm-installed node_modules with pre-built dist/cli.js and bundled ONNX model.
    mkdir -p $out/lib/slopsift
    cp -r ${npmDeps} $out/lib/slopsift/node_modules
    chmod -R u+w $out/lib/slopsift/node_modules

    # Strip non-linux native binaries to save ~40 MB in the store.
    rm -rf $out/lib/slopsift/node_modules/onnxruntime-node/bin/napi-v6/{darwin,win32}

    # autoPatchelfHook runs during fixup and patches the linux .so and .node files.

    # Sandboxed wrapper: unshare --user --net creates an isolated network namespace.
    # Even if a future version adds telemetry or the model-download fallback fires,
    # fetch() will fail — the tool literally cannot open a socket.
    mkdir -p $out/bin
    makeWrapper ${nodejs}/bin/node $out/bin/.slopsift-unwrapped \
      --add-flags "$out/lib/slopsift/node_modules/slopsift/dist/cli.js" \
      --add-flags "--no-download"

    cat > $out/bin/slopsift <<EOF
    #!/bin/sh
    exec ${util-linux}/bin/unshare --user --net -- $out/bin/.slopsift-unwrapped "\$@"
    EOF
    chmod +x $out/bin/slopsift

    # Skill file, content-pinned.
    echo "${skillSha256}  skills/slopsift/SKILL.md" | sha256sum -c -
    install -Dm444 skills/slopsift/SKILL.md -t $out/share/claude-code/skills/slopsift/

    runHook postInstall
  '';

  meta = {
    description = "AI writing-tell linter — network-sandboxed, local ONNX inference";
    homepage = "https://github.com/NikhilVerma/writinglint";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "slopsift";
  };
}
