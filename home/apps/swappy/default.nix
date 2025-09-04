{ config, pkgs, ... }:
{
  home.packages = with pkgs; [
    swappy
  ];

  home.file.".config/swappy/config".text = ''
    [Default]
    save_dir=${config.home.homeDirectory}/Pictures/Screenshots/
    save_filename_format=Screenshot From %Y-%m-%d %H-%M-%S.o.png
    text_font=${config.nix-meridian.fonts.sansSerif.name}
  '';

  systemd.user.services.swappy-launcher = {
    Unit = {
      Description = "Swappy launcher service for Gnome Shell";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.callPackage ./launch/package.nix { name = "launch-swappy"; }}";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
