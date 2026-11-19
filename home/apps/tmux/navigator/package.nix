{
  lib,
  stdenv,
  python3,
  tmux,
  coreutils,
  makeWrapper,
}:
stdenv.mkDerivation {
  pname = "tmux-navigator";
  version = "0";

  # Listed explicitly so a stray __pycache__ from running the tests by hand cannot change the hash.
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./control.py
      ./draw.py
      ./keys.py
      ./main.py
      ./model.py
      ./pane.py
      ./tmux.py
      ./test_draw.py
      ./test_keys.py
      ./test_model.py
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

  # The navigator and its placeholders are recognised by $out/bin/tmux-navigator in their start commands (model.py),
  # so both run from here: the navigator through its own command, a placeholder as a sleep that lasts until killed.
  installPhase = ''
    runHook preInstall
    install -Dm644 -t $out/share/tmux-navigator control.py draw.py keys.py main.py model.py pane.py tmux.py
    makeWrapper ${python3}/bin/python3 $out/bin/tmux-navigator \
      --add-flags $out/share/tmux-navigator/main.py \
      --prefix PATH : ${lib.makeBinPath [ tmux ]} \
      --set TMUX_NAVIGATOR_COMMAND $out/bin/tmux-navigator \
      --set TMUX_NAVIGATOR_PLACEHOLDER $out/bin/tmux-navigator-placeholder
    makeWrapper ${coreutils}/bin/sleep $out/bin/tmux-navigator-placeholder --add-flags infinity
    runHook postInstall
  '';

  meta.mainProgram = "tmux-navigator";
}
