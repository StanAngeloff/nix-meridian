{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    settings."*" = {
      AddKeysToAgent = "yes";

      ControlMaster = "auto";
      ControlPath = "/tmp/ssh_mux_%h_%p_%r";
      ControlPersist = "1h";
    };

    githubAccounts."StanAngeloff" = {
      email = "stanimir@angeloff.name";
    };
  };

  services.ssh-agent = {
    # NOTE: gpg-agent handles SSH via enableSshSupport; both cannot set SSH_AUTH_SOCK
    enable = false;
  };
}
