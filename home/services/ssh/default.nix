{
  programs.ssh = {
    enable = true;
    addKeysToAgent = "yes";
    githubAccounts."StanAngeloff" = {
      email = "stanimir@angeloff.name";
    };
  };

  services.ssh-agent = {
    enable = true;
  };
}
