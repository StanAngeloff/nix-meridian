{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  python3,
}:
buildNpmPackage rec {
  pname = "curlconverter";
  version = "4.12.0";

  src = fetchFromGitHub {
    owner = "curlconverter";
    repo = "curlconverter";
    tag = "v${version}";
    hash = "sha256-eJ8D5HkYSkWqQt/4UTv6/X6coLwcODde6xGEPQXgJRo=";
  };

  npmDepsHash = "sha256-UIbMvw8hkZxtSGInV2+Fjm4DZahrdGtSxi0Unhb5lh8=";

  nativeBuildInputs = [ python3 ];

  npmFlags = [ "--ignore-scripts" ];

  postPatch = ''
    substituteInPlace package.json \
      --replace-fail '"prepare"' '"x-prepare"'
  '';

  buildPhase = ''
    runHook preBuild
    npm rebuild tree-sitter tree-sitter-bash
    npx tsc
    runHook postBuild
  '';

  meta = {
    description = "Convert curl commands to Python, JavaScript, and other languages";
    homepage = "https://github.com/curlconverter/curlconverter";
    license = lib.licenses.mit;
    mainProgram = "curlconverter";
  };
}
