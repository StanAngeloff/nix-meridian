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
  version = "0.11.3";

  src = fetchFromGitHub {
    owner = "openclaw";
    repo = "mcporter";
    tag = "v${finalAttrs.version}";
    hash = "sha256-xBH0OMrAQ3eVqBczzJnbaxbBLo2mRc6cCZBb5w4SkhI=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit pnpm;
    fetcherVersion = 3;
    hash = "sha256-Ga1M3SQBaQnODQXh4+AXQ0FVCr7e8wPpbaV1ffQYNLM=";
  };

  nativeBuildInputs = [
    nodejs_24
    pnpmConfigHook
    pnpm
    npmHooks.npmInstallHook
    makeWrapper
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
