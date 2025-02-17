{ pkgs, ... }:
{
  package = pkgs.viber.overrideAttrs (
    finalAttrs: previousAttrs: {
      installPhase = ''
        ${builtins.replaceStrings [ "\"xcb\"" ] [ "\"wayland\"" ] (previousAttrs.installPhase or "")}

        substituteInPlace $out/share/applications/viber.desktop \
          --replace Path=/opt/viber/ Path=$out/opt/viber/
      '';
    }
  );
}
