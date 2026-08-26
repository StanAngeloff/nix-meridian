{ lib, ... }:
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    includes = [ "config.d/*.conf" ];

    settings."*" = {
      AddKeysToAgent = "yes";

      ControlMaster = "auto";
      ControlPath = "/tmp/ssh_mux_%h_%p_%r";
      ControlPersist = "1h";

      WarnWeakCrypto = "no-pq-kex";
    };

    githubAccounts."StanAngeloff" = {
      email = "stanimir@angeloff.name";
    };
  };

  services.ssh-agent = {
    # NOTE: gpg-agent handles SSH via enableSshSupport; both cannot set SSH_AUTH_SOCK
    enable = false;
  };

  home.activation.sshConfigDropInDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p -m 700 "$HOME/.ssh/config.d"
  '';
}
