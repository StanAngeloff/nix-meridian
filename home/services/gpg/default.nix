{ pkgs, ... }:
{
  programs.gpg = {
    enable = true;

    settings = {
      default-key = "595EA753";
    };

    # scdaemon has its own CCID driver that grabs the reader exclusively;
    # disable it so pcscd arbitrates access for both GnuPG and the browsers
    scdaemonSettings.disable-ccid = true;
  };

  services.gpg-agent = with pkgs; {
    enable = true;
    enableZshIntegration = true;
    enableSshSupport = true;
    # Restricted socket (S.gpg-agent.extra) for forwarding into sandboxes — the Claude Code fence binds it as the in-fence agent socket.
    # Clients on it can sign/decrypt (pinentry-gated as usual) but key management (delete/export/passwd) is refused, and secret key material never crosses.
    enableExtraSocket = true;
    defaultCacheTtl = 3600;
    maxCacheTtl = 86400;
    pinentry = {
      package = pinentry-gnome3;
    };
  };
}
