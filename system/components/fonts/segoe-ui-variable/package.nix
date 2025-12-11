{
  lib,
  stdenvNoCC,
  fetchzip,
}:
# See https://github.com/ewancg/shit/blob/main@%7B2025-02-10%7D/nix/misc/segoe-ui-variable/default.nix
stdenvNoCC.mkDerivation (final: {
  pname = "segoe-ui-variable";
  version = "2.02;210625223709";

  src = fetchzip {
    url = "https://download.microsoft.com/download/f/5/9/f5908651-3551-4a00-b8a0-1b46b5feb723/SegoeUI-VF.zip";
    extension = "zip";
    stripRoot = false;
    hash = "sha256-s82pbi3DQzcV9uP1bySzp9yKyPGkmJ9/m1Q6FRFfGxg=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/{fonts/truetype,licenses/segoe-ui-variable}
    ln -s ${final.src}/EULA.txt $out/share/licenses/segoe-ui-variable/LICENSE
    for font in *.ttf; do
      ln -s ${final.src}/"$font" $out/share/fonts/truetype/"$font"
    done

    runHook postInstall
  '';

  meta = with lib; {
    description = "The new system font for Windows";
    homepage = "https://learn.microsoft.com/en-us/windows/apps/design/downloads/#fonts";
    license = licenses.unfree; # Guessing, haven't read what EULA allows
    maintainers = [ ];
    platforms = platforms.all;
  };
})
