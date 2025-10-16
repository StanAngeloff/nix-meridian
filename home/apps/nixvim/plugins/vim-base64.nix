{ pkgs, ... }:
let
  vim-base64 = (
    pkgs.vimUtils.buildVimPlugin {
      name = "vim-base64";
      src = pkgs.fetchFromGitHub {
        owner = "christianrondeau";
        repo = "vim-base64";
        rev = "d15253105f6a329cd0632bf9dcbf2591fb5944b8";
        hash = "sha256-b60Cs24yxSYlZikEqukJ6m/l6XEUhCIqNW1JWXkbo0Y=";
      };
    }
  );
in
{
  programs.nixvim = {
    extraPlugins = [
      vim-base64
    ];

    globals = {
      vim_base64_disable_default_key_mappings = 1;
    };
  };
}
