{
  lib,
  stdenv,
  fetchFromGitHub,
  nodejs_24,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpm_10,
  npmHooks,
  makeWrapper,
  envchain,
}:
let
  pnpm = pnpm_10;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "mcporter";
  version = "0.11.1";

  src = fetchFromGitHub {
    owner = "openclaw";
    repo = "mcporter";
    tag = "v${finalAttrs.version}";
    hash = "sha256-fhIU5z0H6piHNNHSQ3UQW6IqCdpCTjTxngT7AwQm5S0=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit pnpm;
    fetcherVersion = 3;
    hash = "sha256-TZfEoUSjba8cRz6L9uY2PGskYsR7S/xAahiKLd8dhFM=";
  };

  nativeBuildInputs = [
    nodejs_24
    pnpmConfigHook
    pnpm
    npmHooks.npmInstallHook
    makeWrapper
  ];

  patches = [
    ./patches/openclaw-mcporter-179-skip-proactive-auth-with-cached-tokens.patch
  ];

  buildPhase = ''
    runHook preBuild
    pnpm run build
    runHook postBuild
  '';

  dontNpmPrune = true;

  postFixup = ''
    mv $out/bin/mcporter $out/bin/.mcporter-wrapped
    makeWrapper ${lib.getExe envchain} $out/bin/mcporter \
      --add-flags "mcp_keys $out/bin/.mcporter-wrapped"
  '';

  meta = {
    description = "TypeScript runtime and CLI for connecting to configured Model Context Protocol servers";
    homepage = "https://github.com/openclaw/mcporter";
    changelog = "https://github.com/openclaw/mcporter/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "mcporter";
  };
})
