{ slack }:
slack.overrideAttrs (
  final: prev: {
    installPhase = ''
      ${builtins.replaceStrings
        [
          # Learn more at https://github.com/basecamp/omarchy/issues/2197#issuecomment-3369375848
          "--ozone-platform-hint=auto"
        ]
        [
          "--ozone-platform=wayland"
        ]
        (prev.installPhase or "")
      }
    '';
  }
)
