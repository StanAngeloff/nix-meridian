{
  lib,
  stdenv,
  python3,
  git,
  glib,
  wl-clipboard,
  makeWrapper,
}:
stdenv.mkDerivation {
  pname = "tig-annotate-store";
  version = "0";

  # Listed explicitly so a stray __pycache__ from running the tests by hand cannot change the hash.
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./store.py
      ./test_store.py
    ];
  };

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  # The command and outdated-check tests run git against throwaway repositories.
  doCheck = true;
  nativeCheckInputs = [ git ];
  checkPhase = ''
    runHook preCheck
    ${python3}/bin/python3 -m unittest discover -p 'test_*.py'
    runHook postCheck
  '';

  # git answers the untracked and outdated checks; gio trashes notes; wl-copy takes the export.
  installPhase = ''
    runHook preInstall
    install -Dm644 -t $out/share/tig-annotate-store store.py
    makeWrapper ${python3}/bin/python3 $out/bin/tig-annotate-store \
      --add-flags $out/share/tig-annotate-store/store.py \
      --prefix PATH : ${
        lib.makeBinPath [
          git
          glib
          wl-clipboard
        ]
      }
    runHook postInstall
  '';

  meta.mainProgram = "tig-annotate-store";
}
