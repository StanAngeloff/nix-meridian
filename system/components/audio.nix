{ pkgs, ... }:
{
  services.pulseaudio.enable = false;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;

    # Configure WirePlumber to handle Bluetooth headset profiles.
    wireplumber.extraConfig = {
      "10-bluez" = {
        "monitor.bluez.properties" = {
          "bluez5.enable-bap" = true; # Explicitly enable LE Audio and the LC3 codec
          "bluez5.enable-hw-volume" = true;
          "bluez5.enable-msbc" = true;
          "bluez5.enable-sbc-xq" = true;
          "bluez5.roles" = [
            "a2dp_sink"
            "a2dp_source"
            "bap_sink"
            "bap_source"
            "hsp_hs"
            "hsp_ag"
            "hfp_hf"
            "hfp_ag"
          ];
        };
      };
    };
  };

  security.rtkit.enable = true;

  environment.systemPackages = with pkgs; [
    liblc3 # The required codec for Bluetooth LE Audio
  ];
}
