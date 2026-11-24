{ pkgs, ... }:
let
  toml = pkgs.formats.toml { };
in
{
  # Dictation from the phone (Voxize Remote's server; `cc remote setup` installs and pairs the app).
  imports = [ ./remote ];

  home.packages = [
    pkgs.voxize
  ];

  xdg.configFile."voxize/voxize.toml".source = toml.generate "voxize.toml" {
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
