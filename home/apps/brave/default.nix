{
  config,
  lib,
  pkgs,
  ...
}:
let
  enabledFeatures = [
    # Next-generation Skia rendering backend, replacing GaneshGL.
    "SkiaGraphite"
  ];
  enabledBlinkFeatures = [
    # Enables autoscrolling when the middle mouse button is clicked – Mac, Linux.
    "MiddleClickAutoscroll"
  ];
  disabledFeatures = [
    # "GlobalShortcutsPortal feature is misbehaving on Gnome 48" https://issues.chromium.org/issues/404298968
    "GlobalShortcutsPortal"
  ];

  brave = pkgs.brave.overrideAttrs (prev: {
    # Learn more at https://github.com/NixOS/nixpkgs/pull/378184
    preFixup = (prev.preFixup or "") + ''
      gappsWrapperArgs+=(
        --prefix LD_LIBRARY_PATH : "${pkgs.vulkan-loader}/lib"
      )
    '';
    postFixup = (prev.postFixup or "") + ''
      substituteInPlace $out/bin/brave \
        --replace-fail "--enable-features=" "--enable-features=${builtins.concatStringsSep "," enabledFeatures}," \
        --replace-fail "--disable-features=" "--disable-features=${builtins.concatStringsSep "," disabledFeatures},"
    '';
  });
in
{
  ## Brave uses system-wide policies which are linked outside of Home Manager, see /system/apps/annoyances.nix
  #imports = [
  #  ./policies.nix
  #];

  home.packages = [
    (brave.override {
      # Brave defaults Vulkan to off unlike Chrome, causing sluggish CSS/canvas animations on Intel Iris Xe.
      enableVulkan = true;
      commandLineArgs = "--enable-blink-features=${builtins.concatStringsSep "," enabledBlinkFeatures}";
    })
  ];

  home.file.".local/bin/x-www-browser" = {
    source = "${lib.getExe brave}";
    executable = true;
  };

  # The below is needed for `slackdump` to find Brave (as `brave-browser`).
  home.file.".local/bin/brave-browser" = {
    source = "${lib.getExe brave}";
    executable = true;
  };

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
