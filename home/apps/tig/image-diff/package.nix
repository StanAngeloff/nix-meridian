{
  lib,
  stdenv,
  python3,
  git,
  git-lfs,
  imagemagick,
  makeWrapper,
}:
stdenv.mkDerivation {
  pname = "tig-image-diff";
  version = "0";

  # Listed explicitly so a stray __pycache__ from running the tests by hand cannot change the hash.
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./helper.py
      ./test_helper.py
    ];
  };

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  # The tests render images and read blobs from throwaway repositories, one of them through Git LFS.
  doCheck = true;
  nativeCheckInputs = [
    git
    git-lfs
    imagemagick
  ];
  checkPhase = ''
    runHook preCheck
    ${python3}/bin/python3 -m unittest discover -p 'test_*.py'
    runHook postCheck
  '';

  # git reads the blobs, through the LFS filter in the user's Git configuration; magick renders them.
  installPhase = ''
    runHook preInstall
    install -Dm644 -t $out/share/tig-image-diff helper.py
    makeWrapper ${python3}/bin/python3 $out/bin/tig-image-diff \
      --add-flags $out/share/tig-image-diff/helper.py \
      --prefix PATH : ${
        lib.makeBinPath [
          git
          imagemagick
        ]
      }
    runHook postInstall
  '';

  meta.mainProgram = "tig-image-diff";
}
