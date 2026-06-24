{
  lib,
  viber,
  ffmpeg_4,
}:
viber.overrideAttrs (
  final: prev: {
    # Viber does not reuse the nixpkgs Qt or FFmpeg; it bundles its own copies
    # inside opt/viber. The bundled FFmpeg 4 libraries (libavcodec.so.58,
    # libavformat.so.58, and friends) were linked against codec library sonames
    # that current nixpkgs no longer provides.
    #
    # Present in nixpkgs, but with a drifted soname:
    #   libbluray.so.2: nixpkgs ships .so.3 instead
    #   libtheoraenc.so.1 / libtheoradec.so.1: nixpkgs ships .so.2 instead
    #   libgsm.so.1: nixpkgs ships only the unversioned libgsm.so
    #
    # Absent from the closure entirely:
    #   libgnutls.so.30, liblzma.so.5, libmp3lame.so.0, libvorbis.so.0,
    #   libsoxr.so.0, libgcrypt.so.20, libgpg-error.so.0
    #
    # These are eager (DT_NEEDED) dependencies of the bundled libav*, so the
    # whole Qt 6 Multimedia FFmpeg backend plugin fails to dlopen. Qt then
    # reports "No QtMultimedia backends found" and every video fails to play.
    #
    # ffmpeg_4 provides the same .so.58 ABI from a self-consistent closure.
    # Appending it to libPath places it on the runpath ahead of opt/viber/lib
    # (via the patchelf --set-rpath in installPhase), so it shadows the broken
    # bundled libav* and supplies a complete codec chain. The default ffmpeg is
    # too new to help here: the bundled plugin needs the .so.58 (FFmpeg 4) ABI.
    #
    # Upstream issue: https://github.com/NixOS/nixpkgs/issues/402911
    libPath = prev.libPath + ":" + lib.makeLibraryPath [ ffmpeg_4 ];

    installPhase = ''
      ${builtins.replaceStrings
        [
          # makeWrapper $out/opt/viber/Viber $out/bin/viber \
          "--set QT_QPA_PLATFORM \"xcb\""
          "--set QML2_IMPORT_PATH"
          # substituteInPlace $out/share/applications/viber.desktop \
          "--replace-fail \"/opt/viber/\" \"$out/opt/viber/\""
        ]
        [
          # makeWrapper $out/opt/viber/Viber $out/bin/viber \
          "--set QT_QPA_PLATFORM \"wayland\"" # Force Wayland backend
          "--set FONTCONFIG_FILE \"${./fonts.conf}\" --set QML2_IMPORT_PATH" # Use custom fontconfig
          # substituteInPlace $out/share/applications/viber.desktop \
          "--replace-fail \"/opt/viber/Viber\" \"$out/bin/viber\" --replace-fail \"/opt/viber/\" \"$out/opt/viber/\"" # Update desktop file "Exec" path
        ]
        (prev.installPhase or "")
      }

      substituteInPlace $out/share/applications/viber.desktop \
        --replace Path=/opt/viber/ Path=$out/opt/viber/
    '';
  }
)
