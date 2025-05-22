{
  programs.mise = {
    enable = true;
    enableZshIntegration = true;

    # See https://mise.jdx.dev/configuration.html#global-config-config-mise-config-toml
    globalConfig = {
      settings = {
        idiomatic_version_file_enable_tools = [ "node" ];
      };
    };
  };
}
