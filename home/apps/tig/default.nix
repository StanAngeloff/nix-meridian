{ pkgs-unstable, ... }:
{
  home.packages = with pkgs-unstable; [
    tig
  ];

  home.file.".config/tig/config".source = ./tigrc;
  home.file.".config/tig/vim.tigrc".source = ./vim.tigrc;
}
