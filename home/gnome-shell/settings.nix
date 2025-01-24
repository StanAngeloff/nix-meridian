{ lib, ... }:
{
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      text-scaling-factor = lib.hm.gvariant.mkDouble["1.25"];
    };
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
    "org/gnome/desktop/peripherals/keyboard" = {
      repeat-interval = lib.hm.gvariant.mkUint32 18;
      delay = lib.hm.gvariant.mkUint32 200;
    };
  };
}
