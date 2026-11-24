{
  lib,
  stdenvNoCC,
  androidenv,
  jdk17_headless,
  jre17_minimal,
  runCommand,
  zip,
  python313,
  voxize,
  writeShellScriptBin,
  symlinkJoin,
  android-tools,
  tmux,
  util-linux,
  systemd,
  ffmpeg-headless,
}:
# Voxize Remote: dictate on the client (the Android app in ./android) into the tmux pane its Termux shows, through the
# server (./server/voxize_remote), which feeds the client's audio to this machine's Voxize. `server` is the package;
# `passthru.apk` is the unsigned app and `passthru.tools` what `cc remote setup` signs and installs it with.
let
  version = "0.4.0";
  versionCode = 4;
  minSdk = 30;
  platformVersion = "35";
  buildToolsVersion = "37.0.0";
  # The Python voxize is built with (pkgs/voxize/package.nix): the server goes into its site-packages.
  python = python313;
  # Python sources only: a __pycache__ left by a test run by hand never reaches the store.
  pythonSources =
    directory:
    lib.fileset.toSource {
      root = directory;
      fileset = lib.fileset.fileFilter (file: file.hasExt "py") directory;
    };

  # The Android SDK's licence, accepted for this build only (nixpkgs' config.android_sdk.accept_license stays unset).
  android = (androidenv.override { licenseAccepted = true; }).composeAndroidPackages {
    platformVersions = [ platformVersion ];
    buildToolsVersions = [ buildToolsVersion ];
    includeCmake = false;
    includeEmulator = false;
    includeNDK = false;
    includeSources = false;
    includeSystemImages = false;
  };
  sdk = "${android.androidsdk}/libexec/android-sdk";
  buildTools = "${sdk}/build-tools/${buildToolsVersion}";
  androidJar = "${sdk}/platforms/android-${platformVersion}/android.jar";

  # No Gradle: aapt2 compiles the resources and links them with the manifest, javac and d8 compile, zipalign aligns.
  # Unsigned: the signing key never enters the Nix store (cc remote setup signs at install time).
  androidSource = lib.fileset.toSource {
    root = ./android;
    fileset = ./android;
  };
  apk = stdenvNoCC.mkDerivation {
    pname = "voxize-remote-apk";
    inherit version;
    src = androidSource;
    nativeBuildInputs = [
      jdk17_headless
      zip
    ];
    buildPhase = ''
      runHook preBuild
      ${buildTools}/aapt2 compile --dir res -o resources.zip
      mkdir generated classes dex
      ${buildTools}/aapt2 link -o base.apk -I ${androidJar} --manifest AndroidManifest.xml --java generated \
        --min-sdk-version ${toString minSdk} --target-sdk-version ${platformVersion} \
        --version-code ${toString versionCode} --version-name ${version} resources.zip
      javac -encoding UTF-8 -source 8 -target 8 -Xlint:-options \
        -bootclasspath ${androidJar}:${buildTools}/core-lambda-stubs.jar -d classes \
        $(find src generated -name '*.java')
      ${buildTools}/d8 --release --min-api ${toString minSdk} --lib ${androidJar} --output dex \
        $(find classes -name '*.class')
      cp base.apk unaligned.apk
      (cd dex && zip -q ../unaligned.apk classes.dex)
      ${buildTools}/zipalign -f 4 unaligned.apk aligned.apk
      runHook postBuild
    '';
    installPhase = ''
      install -Dm644 aligned.apk $out/voxize-remote-unsigned.apk
    '';
    passthru = {
      inherit version versionCode;
      packageName = "dev.flemma.voxize.remote";
    };
  };

  # cc remote setup signs with apksigner (one jar of the build tools) and makes its key with keytool, on a Java runtime
  # of just the modules they use: neither the SDK nor a JDK (1.7 GiB between them) reaches the profile.
  jre = jre17_minimal.override {
    jdk = jdk17_headless;
    modules = [
      "java.base"
      "java.logging"
    ];
  };
  apksignerJar = runCommand "apksigner-${buildToolsVersion}.jar" { } ''
    cp ${buildTools}/lib/apksigner.jar $out
  '';
  tools = symlinkJoin {
    name = "voxize-remote-tools";
    paths = [
      (writeShellScriptBin "apksigner" ''
        exec ${jre}/bin/java -Xmx1024M -jar ${apksignerJar} "$@"
      '')
      (writeShellScriptBin "keytool" ''
        exec ${jre}/bin/keytool "$@"
      '')
      (writeShellScriptBin "adb" ''
        exec ${android-tools}/bin/adb "$@"
      '')
    ];
  };
in
# The server rides inside the voxize derivation: buildPythonApplication wraps every bin/ entry with the same PYTHONPATH,
# GI typelibs and libraries as bin/voxize, which the backend it spawns needs.
voxize.overrideAttrs (old: {
  pname = "voxize-remote";
  name = "voxize-remote-${version}";
  inherit version;
  # This package's own version, not voxize's: it is a different program built on voxize's environment.
  __intentionallyOverridingVersion = true;
  # Voxize compresses each recording with ffmpeg found on PATH; a systemd service has no profile to find it in.
  # Appended after voxize's own preFixup fills makeWrapperArgs (GI typelibs, libraries, PYTHONPATH): setting the
  # attribute instead loses all of those, and with them the keyring and the backend's imports.
  preFixup = (old.preFixup or "") + ''
    makeWrapperArgs+=(--prefix PATH : ${lib.makeBinPath [ ffmpeg-headless ]})
  '';
  postInstall = (old.postInstall or "") + ''
    # Only the server's own commands; bin/voxize and friends stay with the installed voxize.
    rm $out/bin/voxize $out/bin/voxize-tui $out/bin/voxize-meet
    cp -r ${pythonSources ./server/voxize_remote} $out/${python.sitePackages}/voxize_remote
    chmod -R u+w $out/lib
    cat > $out/bin/voxize-remote <<PYTHON
    #!${python.interpreter}
    from voxize_remote.server import main
    main()
    PYTHON
    # The same environment for the tests and the fake client: voxize-remote-python -m MODULE ... or SCRIPT ...
    cat > $out/bin/voxize-remote-python <<PYTHON
    #!${python.interpreter}
    import runpy, sys
    arguments = sys.argv[1:]
    if arguments[:1] == ["-m"]:
        sys.argv = arguments[1:]
        runpy.run_module(sys.argv[0], run_name="__main__", alter_sys=True)
    else:
        sys.argv = arguments
        runpy.run_path(sys.argv[0], run_name="__main__")
    PYTHON
    chmod +x $out/bin/voxize-remote $out/bin/voxize-remote-python
  '';
  # The tests run the wrapped commands: a private tmux server, a pty for an attached client, socket activation; and
  # the client's own Java (pairing, error texts) against the server's Python, with a JDK.
  doInstallCheck = true;
  nativeInstallCheckInputs = [
    tmux
    util-linux
    systemd
    jdk17_headless
  ];
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME=$TMPDIR
    PATH=$out/bin:$PATH PYTHONWARNINGS=ignore::ResourceWarning VOXIZE_REMOTE_ANDROID=${androidSource} \
      $out/bin/voxize-remote-python -m unittest discover -s ${pythonSources ./tests}
    runHook postInstallCheck
  '';
  passthru = (old.passthru or { }) // {
    inherit apk tools;
    port = import ./port.nix;
  };
  meta = old.meta // {
    description = "Voxize Remote: dictate on a paired Android client into the tmux pane its Termux shows";
    mainProgram = "voxize-remote";
  };
})
