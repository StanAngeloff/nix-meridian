{ pkgs, ... }:
{
  package = pkgs.viber.overrideAttrs (
    finalAttrs: previousAttrs: {
      installPhase = ''
        ${previousAttrs.installPhase or ""}

        substituteInPlace $out/share/applications/viber.desktop \
          --replace Path=/opt/viber/ Path=$out/opt/viber/
      '';
    }
  );
}
