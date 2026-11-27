{
  lib,
  stdenv,
  python3,
  tmux,
  makeWrapper,
  claudeCopy,
}:
let
  # file_under_pointer.py reads each row as the copy cleanup does, with claude_copy's split_row.
  claudeCopyModules = "${claudeCopy}/share/tmux-claude-copy";
in
stdenv.mkDerivation {
  pname = "tmux-file-under-pointer";
  version = "0";

  # Listed explicitly so a stray __pycache__ from running the tests by hand cannot change the hash.
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./file_under_pointer.py
      ./test_file_under_pointer.py
    ];
  };

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    PYTHONPATH=${claudeCopyModules} ${python3}/bin/python3 -m unittest discover -p 'test_*.py'
    runHook postCheck
  '';

  # tmux reads the screen and keeps the found path; xdg-open comes from the PATH tmux runs it with, as Ghostty's does.
  installPhase = ''
    runHook preInstall
    install -Dm644 -t $out/share/tmux-file-under-pointer file_under_pointer.py
    makeWrapper ${python3}/bin/python3 $out/bin/tmux-file-under-pointer \
      --add-flags $out/share/tmux-file-under-pointer/file_under_pointer.py \
      --prefix PYTHONPATH : ${claudeCopyModules} \
      --prefix PATH : ${lib.makeBinPath [ tmux ]}
    runHook postInstall
  '';

  meta.mainProgram = "tmux-file-under-pointer";
}
