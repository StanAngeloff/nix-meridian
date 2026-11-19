{
  lib,
  stdenv,
  python3,
  tmux,
  coreutils,
  makeWrapper,
  writeText,
  # Claude Code's footer links (home/apps/claude-code/footer-links.nix), which the navigator links too (links.py).
  links,
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
      ./links.py
      ./main.py
      ./model.py
      ./pane.py
      ./processes.py
      ./tmux.py
      ./widgets.py
      ./test_draw.py
      ./test_keys.py
      ./test_links.py
      ./test_model.py
      ./test_processes.py
      ./test_widgets.py
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
    install -Dm644 -t $out/share/tmux-navigator control.py draw.py keys.py links.py main.py model.py pane.py processes.py tmux.py widgets.py
    install -Dm644 ${writeText "tmux-navigator-links.json" (builtins.toJSON links)} $out/share/tmux-navigator/links.json
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
