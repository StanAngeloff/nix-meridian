{ pkgs, ... }:
{
  home.packages = [ pkgs.dropbox ];

  home.file.".config/autostart/dropbox.desktop".text = ''
    [Desktop Entry]
    Categories=Network;FileTransfer
    Comment=Sync your files across computers and to the web
    Exec=${pkgs.dropbox}/bin/dropbox
    GenericName=File Synchronizer
    Icon=dropbox
    Name=Dropbox
    StartupNotify=false
    Type=Application
    Version=1.4
  '';
}
