{
  config,
  lib,
  pkgs,
  ...
}:
let
  enabledFeatures = [
    # Route ANGLE through Vulkan instead of OpenGL. All three must be enabled together on Linux
    # (per ANGLE Vulkan backend developer). Eliminates 80-150ms GPU stalls on animation-heavy pages
    # while keeping hardware video decode working (unlike raw --enable-features=Vulkan alone).
    "Vulkan"
    "DefaultANGLEVulkan"
    "VulkanFromANGLE"
    # Bypass VA-API driver version checks that can reject working Intel/AMD drivers.
    "VaapiIgnoreDriverChecks"
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

      # Brave bundles a libvulkan.so.1 that only finds SwiftShader (Vulkan 1.0.5), but ANGLE
      # requires Vulkan 1.1+. Replace it with the real loader so ANGLE discovers the Mesa driver.
      # Chrome's Nix package (google-chrome/package.nix) does the same thing.
      ln -sf "${pkgs.vulkan-loader}/lib/libvulkan.so.1" "$out/opt/brave.com/brave/libvulkan.so.1"

      # Give ANGLE's libraries (libEGL.so, libGLESv2.so) the same rpath as the main binary so
      # they can find libvulkan and libGL at runtime. Also borrowed from Chrome's Nix package.
      # Brave 1.93+ may no longer bundle these libraries.
      for lib in $out/opt/brave.com/brave/lib*GL*; do
        [ -f "$lib" ] && ${pkgs.patchelf}/bin/patchelf --set-rpath "$(${pkgs.patchelf}/bin/patchelf --print-rpath $out/opt/brave.com/brave/brave)" "$lib"
      done
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
      ## NOTE: Not needed — Vulkan is enabled via ANGLE flags in enabledFeatures above.
      ## The package-level enableVulkan only adds "Vulkan" to features, which we already do.
      #enableVulkan = true;
      commandLineArgs = "--ignore-gpu-blocklist --enable-blink-features=${builtins.concatStringsSep "," enabledBlinkFeatures}";
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
