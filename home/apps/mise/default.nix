{ pkgs-unstable, ... }:
{
  programs.mise = {
    enable = true;
    enableZshIntegration = true;

    package = pkgs-unstable.mise;

    # See https://mise.jdx.dev/configuration.html#global-config-config-mise-config-toml
    globalConfig = {
      settings = {
        idiomatic_version_file_enable_tools = [ "node" ];

        node = {
          # Disable compiling Node.js from source when installing versions, `programs.nix-ld.enable` must be true.
          compile = false;
        };
      };
    };
  };
}
