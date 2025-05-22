{ pkgs, ... }:
{
  programs.gpg = {
    enable = true;

    settings = {
      default-key = "595EA753";
    };
  };

  services.gpg-agent = with pkgs; {
    enable = true;
    enableZshIntegration = true;
    enableSshSupport = true;
    defaultCacheTtl = 3600;
    maxCacheTtl = 86400;
    pinentry = {
      package = pinentry-gnome3;
    };
  };
}
