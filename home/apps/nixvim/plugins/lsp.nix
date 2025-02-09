{ pkgs, ... }:
{
  programs.nixvim = {
    extraPackages = with pkgs; [
      nixd
    ];

    plugins = {
      lsp = {
        enable = true;

        servers = {
          nixd = {
            enable = true;
          };

          jsonls = {
            enable = true;
          };

          yamlls = {
            enable = true;
          };
        };
      };
    };
  };
}
