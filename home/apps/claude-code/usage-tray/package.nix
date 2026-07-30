{
  lib,
  stdenv,
  python3,
  gtk3,
  libayatana-appindicator,
  libsoup_3,
  gobject-introspection,
  wrapGAppsHook3,
}:
let
  python = python3.withPackages (ps: [ ps.pygobject3 ]);
in
stdenv.mkDerivation {
  pname = "claude-usage-tray";
  version = "0";

  # Listed explicitly so a stray __pycache__ from running the tests by hand cannot change the hash.
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./usage.py
      ./client.py
      ./tray.py
      ./main.py
      ./test_usage.py
      ./icons/claude-symbolic.svg
      ./icons/claude-dim-symbolic.svg
    ];
  };

  nativeBuildInputs = [
    gobject-introspection
    wrapGAppsHook3
  ];

  # GTK 3 rather than 4 is forced by libayatana-appindicator, which is a GTK 3 library. It costs
  # nothing here: the application has no windows, so GTK never draws anything the user sees.
  buildInputs = [
    python
    gtk3
    libayatana-appindicator
    libsoup_3
  ];

  dontBuild = true;

  # The pure module carries every decision the program makes, so its tests are the whole check.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ${python}/bin/python3 -m unittest discover -p 'test_*.py'
    runHook postCheck
  '';

  # Wrap by hand so gappsWrapperArgs (which carries GI_TYPELIB_PATH) can be spliced into the same
  # wrapper that points Python at main.py.
  dontWrapGApps = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 -t $out/share/claude-usage-tray usage.py client.py tray.py main.py
    # Beside the modules, because tray.py resolves them relative to itself.
    install -Dm644 -t $out/share/claude-usage-tray/icons icons/*.svg
    runHook postInstall
  '';

  # Not installPhase: wrapGAppsHook3 fills gappsWrapperArgs from a preFixupPhases hook, which runs
  # after the install. Wrapping any earlier splices an empty array and the typelibs go missing.
  preFixup = ''
    makeWrapper ${python}/bin/python3 $out/bin/claude-usage-tray \
      --add-flags $out/share/claude-usage-tray/main.py \
      "''${gappsWrapperArgs[@]}"
  '';

  meta.mainProgram = "claude-usage-tray";
}
