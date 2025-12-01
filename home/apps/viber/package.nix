{ viber }:
viber.overrideAttrs (
  finalAttrs: previousAttrs: {
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
        (previousAttrs.installPhase or "")
      }

      substituteInPlace $out/share/applications/viber.desktop \
        --replace Path=/opt/viber/ Path=$out/opt/viber/
    '';
  }
)
