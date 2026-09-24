{
  lib,
  stdenv,
  buildNpmPackage,
  fetchzip,
  fetchurl,
  nodejs_24,
  autoPatchelfHook,
  util-linux,
}:
let
  # Claude Code ingests this skill as a prompt, verbatim, so it is pinned by content rather than by trust.
  # It has a pin of its own so that a routine bump for a bug fix cannot carry rewritten instructions along with it, silently.
  # A changed file fails the fetch instead, so changing what Claude is told stays a deliberate act.
  # Update it only after reading the upstream diff, which update.sh shows before it asks.
  skillSha256 = "9877757bb95743b19894b750ac20d314ee0343a531b522f180216c8bd62ee8f0";
in
buildNpmPackage (finalAttrs: {
  pname = "slopsift";
  version = "0.11.0";

  # The published npm package, which ships dist/cli.js already compiled and the ONNX model it runs.
  src = fetchzip {
    url = "https://registry.npmjs.org/slopsift/-/slopsift-${finalAttrs.version}.tgz";
    hash = "sha256-UglXnVcop5YWI3THjIibS4ZxKkBqR0qtVm7zEs7oyfY=";
  };

  # The npm package has no lockfile, so package-lock.json next to this file pins its dependency tree.
  # slopsift declares its dependencies as version ranges,
  # so without the lockfile each build would take whatever npm serves that day.
  # update.sh regenerates it with `npm install --package-lock-only` inside the unpacked npm package.
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-bEX0ruYFwMY8H3NdiS6eiXhYTX3VaBJchDJlnGQ+KhA=";

  nodejs = nodejs_24;

  # The build and prepack scripts recompile dist/ with TypeScript, which is not among the package's dependencies.
  dontNpmBuild = true;
  npmPackFlags = [ "--ignore-scripts" ];

  # onnxruntime-node's install script downloads the binaries it does not bundle (the CUDA builds) from NuGet.
  # The bundled CPU binaries are all slopsift needs.
  env.ONNXRUNTIME_NODE_INSTALL = "skip";

  # onnxruntime-node ships prebuilt linux binaries that link libstdc++. autoPatchelfHook patches them during fixup.
  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];

  makeWrapperArgs = [
    # ONNX Runtime includes Microsoft's telemetry client, which keeps a device ID under ~/.cache/Microsoft.
    # The network namespace below blocks what it would send. ORT_DISABLE_TELEMETRY turns it off.
    # nixfmt: off
    "--set" "ORT_DISABLE_TELEMETRY" "1"
    "--add-flags"
    "--no-download"
    # nixfmt: on, as: shell-args
  ];

  postInstall = ''
    # Strip non-linux native binaries to save ~40 MB in the store.
    rm -rf $out/lib/node_modules/slopsift/node_modules/onnxruntime-node/bin/napi-v6/{darwin,win32}

    # Sandboxed wrapper: unshare --user --net creates an isolated network namespace.
    # Even if a future version adds telemetry or the model-download fallback fires,
    # fetch() will fail — the tool literally cannot open a socket.
    mv $out/bin/slopsift $out/bin/.slopsift-unwrapped
    cat > $out/bin/slopsift <<EOF
    #!/bin/sh
    exec ${util-linux}/bin/unshare --user --net -- $out/bin/.slopsift-unwrapped "\$@"
    EOF
    chmod +x $out/bin/slopsift

    install -Dm444 ${finalAttrs.passthru.skill} $out/share/claude-code/skills/slopsift/SKILL.md
  '';

  passthru = {
    skill = fetchurl {
      url = "https://raw.githubusercontent.com/NikhilVerma/writinglint/slopsift@${finalAttrs.version}/skills/slopsift/SKILL.md";
      sha256 = skillSha256;
    };
    updateScript = ./update.sh;
  };

  meta = {
    description = "AI writing-tell linter — network-sandboxed, local ONNX inference";
    homepage = "https://github.com/NikhilVerma/writinglint";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "slopsift";
  };
})
