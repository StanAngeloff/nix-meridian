{ pkgs, lib, ... }:
with pkgs;
let
  package = stdenv.mkDerivation rec {
    pname = "gnome-shell-extension-no-titlebar-when-maximized";
    version = "17";

    src = fetchFromGitHub {
      owner = "alecdotninja";
      repo = "no-titlebar-when-maximized";
      rev = "v${version}";
      hash = "sha256-NlQKRt3lnn6fjP5JCyjF7QAIC5egltOIOICRPNixymk=";
    };

    passthru = {
      extensionUuid = "no-titlebar-when-maximized@alec.ninja";
      extensionPortalSlug = "no-titlebar-when-maximized";
    };

    patches = [
      (replaceVars ./no-titlebar-when-maximized-paths.patch {
        xprop = "${xorg.xprop}/bin/xprop";
      })
    ];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/gnome-shell/extensions/${passthru.extensionUuid}
      cp extension.js metadata.json $out/share/gnome-shell/extensions/${passthru.extensionUuid}
      runHook postInstall
    '';

    meta = with lib; {
      description = "Hides the classic title bar of maximized X.Org windows";
      homepage = "https://github.com/alecdotninja/no-titlebar-when-maximized";
      license = licenses.gpl2;
      platforms = platforms.linux;
    };
  };
in
{
  programs.gnome-shell.extensions = [ { package = package; } ];
}
