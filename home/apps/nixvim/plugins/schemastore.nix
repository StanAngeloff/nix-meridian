{ pkgs-unstable, ... }:
{
  programs.nixvim.plugins.schemastore = {
    enable = true;
    package = pkgs-unstable.vimPlugins.SchemaStore-nvim;

    json = {
      enable = true;
    };

    yaml = {
      enable = true;
    };
  };
}
