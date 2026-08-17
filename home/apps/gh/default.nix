{ pkgs-unstable, ... }:
{
  programs.gh = {
    enable = true;
    package = pkgs-unstable.gh;

    extensions = with pkgs-unstable; [
      gh-stack
    ];

    hosts = {
      "github.com" = {
        git_protocol = "ssh";
        user = "StanAngeloff";
      };
    };
  };
}
