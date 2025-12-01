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
    enable = true;
  };
}
