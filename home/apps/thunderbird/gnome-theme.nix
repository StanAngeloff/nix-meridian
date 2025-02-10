{ pkgs, lib, ... }:
with pkgs;
let
  theme = stdenv.mkDerivation rec {
    pname = "thunderbird-gnome-theme";
    version = "1994e7ec06";

    src = fetchFromGitHub {
      owner = "rafaelmardojai";
      repo = "thunderbird-gnome-theme";
      rev = "${version}";
      hash = "sha256-i0Uo5EN45rlGuR85hvPet43zW/thOQTwHypVg9shTHU=";
    };

    installPhase = ''
      runHook preInstall

      mkdir -p $out
      cp -R icon.svg userContent.css userChrome.css theme/ $out

      runHook postInstall
    '';

    meta = with lib; {
      description = " A GNOME theme for Thunderbird";
      homepage = "https://github.com/rafaelmardojai/thunderbird-gnome-theme";
      license = licenses.unlicense;
      platforms = platforms.linux;
    };
  };
in
{
  programs.thunderbird = {
    settings = {
      "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      "svg.context-properties.content.enabled" = true;
    };

    profiles.default.userContent = ''
      @import url("${theme}/userContent.css");
    '';

    profiles.default.userChrome = ''
      @import url("${theme}/userChrome.css");

      /* Highlight tagged messages */
      #threadTree tr[data-properties~="tagged"].card-layout .card-container :is(.sender, .date, .subject) { color: var(--tag-color) !important; }
      #threadTree tr[data-properties~="tagged"].card-layout.selected .card-container { background-color: color-mix(in srgb, var(--tag-color) 20%, transparent) !important; }
    '';
  };
}
