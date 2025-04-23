{ pkgs, ... }:
{
  ## Brave uses system-wide policies which are linked outside of Home Manager, see /system/apps/annoyances.nix
  #imports = [
  #  ./policies.nix
  #];

  home.packages = with pkgs; [
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

    (pkgs.callPackage ./x-www-browser.nix {
      package = brave;
      execPath = "brave";
    })
  ];
}
