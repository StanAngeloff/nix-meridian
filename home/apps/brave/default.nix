{
  config,
  lib,
  pkgs,
  ...
}:
let
  brave = pkgs.brave;
  x-www-browser = pkgs.callPackage ./x-www-browser.nix {
    execPath = lib.getExe brave;
  };
in
{
  ## Brave uses system-wide policies which are linked outside of Home Manager, see /system/apps/annoyances.nix
  #imports = [
  #  ./policies.nix
  #];

  home.packages = [
    (brave.override (
      let
        features = [
          # Enables autoscrolling when the middle mouse button is clicked – Mac, Linux.
          "MiddleClickAutoscroll"
        ];
      in
      {
        commandLineArgs = builtins.replaceStrings [ "\n" ] [ " " ] ''
          --enable-blink-features=${builtins.concatStringsSep "," features}
        '';
      }
    ))

    x-www-browser
  ];

  home.activation.updateBravePreferences =
    let
      jq = "${lib.getExe pkgs.jq}";
      sponge = "${lib.getBin pkgs.moreutils}/bin/sponge";
    in
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      preferencesFile="${config.home.homeDirectory}/.config/BraveSoftware/Brave-Browser/Default/Preferences"

      if [[ ! -f "$preferencesFile" ]]; then
        echo "Creating Brave preferences file..."

        mkdir -p "$(dirname "$preferencesFile")"
        echo "{}" > "$preferencesFile"
        chmod 644 "$preferencesFile"
      fi

      ${jq} ${lib.strings.escapeShellArg ".webkit.webprefs.fonts = ${
        builtins.toJSON {
          "fixed" = {
            "Zyyy" = config.nix-meridian.fonts.monospace.name;
          };
          "sansserif" = {
            "Zyyy" = config.nix-meridian.fonts.sansSerif.name;
          };
          "serif" = {
            "Zyyy" = config.nix-meridian.fonts.serif.name;
          };
          "standard" = {
            "Zyyy" = config.nix-meridian.fonts.serif.name;
          };
        }
      }"} "$preferencesFile" | ${sponge} "$preferencesFile"
    '';
}
