{
  lib,
  python3,
  difftastic,
  makeWrapper,
}:
let
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./difft-unified.py
      ./pager.py
    ];
  };

  pager = python3.pkgs.buildPythonApplication {
    pname = "difft-unified-pager";
    version = "0.1.0";
    format = "other";

    inherit src;

    dontBuild = true;

    installPhase = ''
      install -Dm755 pager.py $out/bin/difft-unified-pager
    '';

    meta = {
      description = "Pager for difft-unified with tig-like cursor navigation";
      mainProgram = "difft-unified-pager";
    };
  };
in
python3.pkgs.buildPythonApplication {
  pname = "difft-unified";
  version = "0.1.0";
  format = "other";

  inherit src;

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    install -Dm755 difft-unified.py $out/bin/difft-unified

    wrapProgram $out/bin/difft-unified \
      --prefix PATH : ${lib.makeBinPath [ difftastic ]}
  '';

  passthru = { inherit pager; };

  meta = {
    description = "Git external diff driver wrapping difftastic JSON into tig-style unified diff";
    mainProgram = "difft-unified";
  };
}
