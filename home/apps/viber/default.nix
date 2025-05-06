{ viber }:
viber.overrideAttrs (
  finalAttrs: previousAttrs: {
    installPhase = ''
      ${builtins.replaceStrings
        [
          "--set QT_QPA_PLATFORM \"xcb\""
          "--set QML2_IMPORT_PATH"
        ]
        [
          "--set QT_QPA_PLATFORM \"wayland\""
          "--set FONTCONFIG_FILE \"${./fonts.conf}\" --set QML2_IMPORT_PATH"
        ]
        (previousAttrs.installPhase or "")
      }

      substituteInPlace $out/share/applications/viber.desktop \
        --replace Path=/opt/viber/ Path=$out/opt/viber/
    '';
  }
)
