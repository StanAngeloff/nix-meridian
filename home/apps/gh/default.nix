{ pkgs-unstable, ... }:
let
  gh = pkgs-unstable.gh;
  gh-stack = pkgs-unstable.gh-stack;
in
{
  programs.gh = {
    enable = true;
    package = gh;

    extensions = [
      gh-stack
    ];

    hosts = {
      "github.com" = {
        git_protocol = "ssh";
        user = "StanAngeloff";
      };
    };
  };

  home.file.".claude/skills/gh-stack".source = "${gh-stack}/share/skills/gh-stack/gh-stack";
}
