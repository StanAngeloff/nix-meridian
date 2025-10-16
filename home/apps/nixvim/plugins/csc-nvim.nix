{ config, pkgs, ... }:
let
  csc-nvim = (
    pkgs.vimUtils.buildVimPlugin rec {
      name = "csc-nvim";
      version = "master@{2025-10-16T09:50:00Z}";

      src = pkgs.fetchFromGitHub {
        owner = "yus-works";
        repo = "csc.nvim";
        rev = builtins.replaceStrings [ "@" "{" "}" ":" ] [ "%40" "%7B" "%7D" "%3A" ] version;
        hash = "sha256-HCNyB8j2fMfT/WnIcr6WCMJ5GOArCZYuQswX7ZhoHjs=";
      };

      nvimRequireCheck = [
        "csc"
        # "csc.cmp"
        "csc.blink-cmp"
        "csc.commands"
        "csc.git"
        "csc.logger"
        "csc.parser"
      ];
    }
  );
  csc-settings = { };
in
{
  programs.nixvim = {
    extraPlugins = [ csc-nvim ];

    extraConfigLua = with config.lib.nixvim; ''
      require("csc").setup(${toLuaObject csc-settings});
    '';
  };
}
