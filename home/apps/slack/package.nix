{ slack }:
slack.overrideAttrs (
  finalAttrs: previousAttrs: {
    installPhase = ''
      ${builtins.replaceStrings
        [
          # Learn more at https://github.com/basecamp/omarchy/issues/2197#issuecomment-3369375848
          "--ozone-platform-hint=auto"
        ]
        [
          "--ozone-platform=wayland"
        ]
        (previousAttrs.installPhase or "")
      }
    '';
  }
)
