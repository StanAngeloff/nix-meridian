{ pkgs, ... }:
let
  toml = pkgs.formats.toml { };
in
{
  home.packages = [
    pkgs.voxize
  ];

  xdg.configFile."voxize/voxize.toml".source = toml.generate "voxize.toml" {
    ducking = {
      apps = [ ];
    };
    storage = {
      max_sessions = 1000;
      max_age_days = 30;
      meeting = {
        max_sessions = 1000000;
        max_age_days = 3650;
      };
    };
  };
}
