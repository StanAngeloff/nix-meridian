{
  lib,
  buildNpmPackage,
  fetchzip,
  jq,
  nodejs_24,
  versionCheckHook,
}:
buildNpmPackage (finalAttrs: {
  pname = "cc-safety-net";
  version = "2.4.11";

  # The published npm package, which ships dist/ already bundled: the bundle imports only Node builtins and its own files.
  src = fetchzip {
    url = "https://registry.npmjs.org/cc-safety-net/-/cc-safety-net-${finalAttrs.version}.tgz";
    hash = "sha256-DPU4eAOaoQgsoDyXcEtv9qN7W/63lm2JKoRKx566IAg=";
  };

  # The npm package has no lockfile, so package-lock.json next to this file pins its dependency tree, which is empty.
  # Its package.json still lists upstream's development tools (TypeScript, linters, `@types/bun: latest`), and the bundle
  # needs none of them, so they are dropped here and in update.sh, which regenerates the lockfile the same way.
  # jq comes by store path because the dependency fetcher runs this hook too, without the build's inputs.
  postPatch = ''
    ${lib.getExe jq} 'del(.devDependencies)' package.json >package.json.new
    mv package.json.new package.json
    cp ${./package-lock.json} package-lock.json
  '';

  forceEmptyCache = true;
  npmDepsHash = "sha256-NGHLfRyBd2ocJoZPxd/cf+6mhzyKzYfdyi5YClBXM/k=";
  # With no dependencies npm creates no node_modules, which the install phase copies.
  preInstall = "mkdir node_modules/";

  nodejs = nodejs_24;

  # The build script rebundles dist/ with bun, which the published package already did.
  dontNpmBuild = true;
  npmPackFlags = [ "--ignore-scripts" ];

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru.updateScript = ./update.sh;

  meta = {
    description = "Coding agent hook that blocks destructive commands and secret file access";
    homepage = "https://github.com/kenryu42/cc-safety-net";
    changelog = "https://github.com/kenryu42/cc-safety-net/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    inherit (nodejs_24.meta) platforms;
    mainProgram = "cc-safety-net";
  };
})
