{
  lib,
  stdenv,
  python3,
  makeWrapper,
  shellcheck,
  dash,
  openssh,
  coreutils,
  writeShellApplication,
  tailscale,
  # The `tailscale up` line for this machine's very first login, built by the caller from services.tailscale.extraSetFlags.
  firstLoginCommand,
}:
let
  # `cc remote setup`: the pairing server (pairing_server.py around the pure pairing.py), serving setup-termux.sh.
  cc-remote-setup = stdenv.mkDerivation {
    pname = "cc-remote-setup";
    version = "0";

    # Listed explicitly so a stray __pycache__ from running the tests by hand cannot change the hash.
    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [
        ./pairing.py
        ./pairing_server.py
        ./setup-termux.sh
        ./test_pairing.py
        ./test_pairing_server.py
        ./test_setup_termux.py
      ];
    };

    nativeBuildInputs = [ makeWrapper ];

    dontBuild = true;

    # dash checks the bootstrap parses as POSIX sh; shellcheck gates the Termux script, which never runs on this machine;
    # the Termux script's tests edit known_hosts with ssh-keygen.
    doCheck = true;
    nativeCheckInputs = [
      shellcheck
      dash
      openssh
    ];
    checkPhase = ''
      runHook preCheck
      ${python3}/bin/python3 -m unittest discover -p 'test_*.py'
      shellcheck setup-termux.sh
      runHook postCheck
    '';

    # The tailscale CLI comes from the same package as the running daemon, so the JSON it prints is the version tested against.
    installPhase = ''
      runHook preInstall
      install -Dm644 -t $out/share/cc-remote-setup pairing.py pairing_server.py setup-termux.sh
      makeWrapper ${python3}/bin/python3 $out/bin/cc-remote-setup \
        --add-flags $out/share/cc-remote-setup/pairing_server.py \
        --prefix PATH : ${lib.makeBinPath [ tailscale ]} \
        --set CC_REMOTE_FIRST_LOGIN_COMMAND ${lib.escapeShellArg firstLoginCommand}
      runHook postInstall
    '';

    meta.mainProgram = "cc-remote-setup";
  };
in
writeShellApplication {
  name = "cc-remote";
  runtimeInputs = [ coreutils ];
  text =
    builtins.replaceStrings
      [ "@setupExe@" "@firstLoginCommand@" ]
      [ (lib.getExe cc-remote-setup) firstLoginCommand ]
      (builtins.readFile ./remote.sh);
  passthru.setup = cc-remote-setup;
}
