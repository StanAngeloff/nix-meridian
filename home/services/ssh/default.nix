{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    matchBlocks."*" = {
      addKeysToAgent = "yes";

      controlMaster = "auto";
      controlPath = "/tmp/ssh_mux_%h_%p_%r";
      controlPersist = "1h";
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
