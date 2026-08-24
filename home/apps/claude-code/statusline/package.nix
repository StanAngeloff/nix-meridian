{
  lib,
  stdenv,
  python3,
  git,
  makeWrapper,
}:
stdenv.mkDerivation {
  pname = "claude-code-statusline";
  version = "0";

  # Listed explicitly so a stray __pycache__ from running the tests by hand cannot change the hash.
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./palette.py
      ./fit.py
      ./render.py
      ./segments.py
      ./main.py
      ./test_fit.py
      ./test_render.py
      ./test_segments.py
      ./test_main.py
      ./test_golden.py
    ];
  };

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  # The pure modules carry every decision the program makes, so their tests are the whole check.
  # git itself is a check-time dependency too: GitBranch's tests exercise the real binary against a
  # throwaway repository, and the sandboxed checkPhase has no PATH beyond stdenv without this.
  doCheck = true;
  nativeCheckInputs = [ git ];
  checkPhase = ''
    runHook preCheck
    ${python3}/bin/python3 -m unittest discover -p 'test_*.py'
    runHook postCheck
  '';

  # git is the only thing the line shells out for: the branch, once per render.
  installPhase = ''
    runHook preInstall
    install -Dm644 -t $out/share/claude-code-statusline palette.py fit.py render.py segments.py main.py
    makeWrapper ${python3}/bin/python3 $out/bin/claude-code-statusline \
      --add-flags $out/share/claude-code-statusline/main.py \
      --prefix PATH : ${lib.makeBinPath [ git ]}
    runHook postInstall
  '';

  meta.mainProgram = "claude-code-statusline";
}
