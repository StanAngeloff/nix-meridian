{
  lib,
  stdenv,
  python3,
  tmux,
  coreutils,
  wl-clipboard,
  makeWrapper,
}:
stdenv.mkDerivation {
  pname = "tmux-claude-copy";
  version = "0";

  # Listed explicitly so a stray __pycache__ from running the tests by hand cannot change the hash.
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./claude_copy.py
      ./test_claude_copy.py
    ];
  };

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ${python3}/bin/python3 -m unittest discover -p 'test_*.py'
    runHook postCheck
  '';

  # tmux takes the cleaned copy back; timeout and wl-copy serve the y binding.
  installPhase = ''
    runHook preInstall
    install -Dm644 -t $out/share/tmux-claude-copy claude_copy.py
    makeWrapper ${python3}/bin/python3 $out/bin/tmux-claude-copy \
      --add-flags $out/share/tmux-claude-copy/claude_copy.py \
      --prefix PATH : ${
        lib.makeBinPath [
          tmux
          coreutils
          wl-clipboard
        ]
      }
    runHook postInstall
  '';

  meta.mainProgram = "tmux-claude-copy";
}
