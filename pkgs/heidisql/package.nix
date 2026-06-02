{
  lib,
  stdenv,
  fetchFromGitHub,
  lazarus-qt6,
  fpc,
  libqtpas,
  qtbase,
  wrapQtAppsHook,
  openssl,
  libmysqlclient,
  postgresql,
  sqlite,
  freetds,
  libx11,
  gtkTheme ? "Adwaita:light",
}:

let
  version = "13.0-preview-2026-06-01";
in
stdenv.mkDerivation {
  pname = "heidisql";
  inherit version;

  # From the 'lazarus' branch; no tagged release yet.
  src = fetchFromGitHub {
    owner = "HeidiSQL";
    repo = "HeidiSQL";
    rev = "7cfdb9763108d22ced4945e6d866743e6e62bc25";
    hash = "sha256-cZb29mXb26SE42OKZfTfIwIOnoAC39dnCPLfOLPWXl4=";
  };

  nativeBuildInputs = [
    lazarus-qt6
    fpc
    wrapQtAppsHook
  ];

  buildInputs = [
    libqtpas
    qtbase
    openssl
    libmysqlclient
    postgresql.lib
    sqlite
    freetds
  ];

  postPatch =
    let
      pascalStr = s: "'${s}'";
      ldconfigLines = [
        "libmariadb.so.3 (libc6,x86-64) => ${lib.getLib libmysqlclient}/lib/mariadb/libmariadb.so.3"
        "libpq.so.5 (libc6,x86-64) => ${lib.getLib postgresql.lib}/lib/libpq.so.5"
        "libsqlite3.so.0 (libc6,x86-64) => ${lib.getLib sqlite}/lib/libsqlite3.so.0"
        "libsybdb.so.5 (libc6,x86-64) => ${lib.getLib freetds}/lib/libsybdb.so.5"
      ];
      pascalConcat = lib.concatStringsSep " + #10 + " (map pascalStr ldconfigLines);
      oldLine = "Process.RunCommandInDir('', '/sbin/ldconfig', ['-p'], LibMapOutput);";
      newLine = "LibMapOutput := ${pascalConcat};";
    in
    ''
      substituteInPlace source/dbconnection.pas \
        --replace-fail ${lib.escapeShellArg oldLine} ${lib.escapeShellArg newLine}
    '';

  buildPhase = ''
    runHook preBuild
    HOME=$TMPDIR lazbuild -B --bm=Release --ws=qt6 \
      --lazarusdir=${lazarus-qt6}/share/lazarus \
      heidisql.lpi
    runHook postBuild
  '';

  # OpenSSL is loaded by FPC's opensslsockets unit via LD_LIBRARY_PATH, not ldconfig.
  qtWrapperArgs = [
    "--prefix LD_LIBRARY_PATH : ${
      lib.makeLibraryPath [
        libqtpas
        libx11
        openssl
        libmysqlclient
        postgresql.lib
        sqlite
        freetds
      ]
    }"
    "--set GTK_THEME ${gtkTheme}"
  ];

  dontWrapQtApps = true;

  # HeidiSQL resolves locale and INI files relative to the binary via GetAppDir,
  # so the binary must be co-located with these resources.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/heidisql/locale $out/share/applications \
      $out/share/icons/hicolor/256x256/apps

    install -m755 out/heidisql $out/share/heidisql/heidisql
    cp extra/locale/*.mo $out/share/heidisql/locale/
    cp extra/ini/*.ini $out/share/heidisql/

    cp res/deb-package-icon.png $out/share/icons/hicolor/256x256/apps/heidisql.png

    substituteInPlace package-skeleton/usr/share/applications/heidisql.desktop \
      --replace-fail "Exec=heidisql" "Exec=$out/bin/heidisql" \
      --replace-fail "Comment=A lightweight interface to MySQL" \
        "Comment=Powerful SQL client for everyday database work" \
      --replace-fail "Categories=Development;" "Categories=Development;Database;" \
      --replace-fail "Icon=heidisql" \
        "Icon=$out/share/icons/hicolor/256x256/apps/heidisql.png"
    cp package-skeleton/usr/share/applications/heidisql.desktop \
      $out/share/applications/heidisql.desktop

    wrapQtApp $out/share/heidisql/heidisql
    ln -s $out/share/heidisql/heidisql $out/bin/heidisql

    runHook postInstall
  '';

  enableParallelBuilding = false;

  meta = {
    description = "Powerful SQL client for everyday database work";
    homepage = "https://www.heidisql.com";
    license = lib.licenses.gpl2Plus;
    mainProgram = "heidisql";
    platforms = [ "x86_64-linux" ];
  };
}
