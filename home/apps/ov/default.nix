{
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:
{
  home.packages = [
    pkgs-unstable.ov
  ];

  home.file.".config/ov/config.yml".source = ./ov-less.yaml;

  programs.git = {
    iniContent = {
      # NOTE: This overrides the "core.pager" setting from "diff-so-fancy.enable".
      core.pager = lib.mkForce "${pkgs.diff-so-fancy}/bin/diff-so-fancy | ${pkgs-unstable.ov}/bin/ov ${
        lib.escapeShellArgs [ "--quit-if-one-screen" ]
      }";
    };

    settings = {
      pager = {
        diff = "${pkgs.diff-so-fancy}/bin/diff-so-fancy | ${pkgs-unstable.ov}/bin/ov ${
          lib.escapeShellArgs [
            # See https://github.com/so-fancy/diff-so-fancy/blob/v1.4.4/pro-tips.md#moving-around-in-the-diff
            # nixfmt: off
            "--section-delimiter" "^(Date|added|deleted|modified): "
            "--section-start" "-1"
            "--section-header-num" "3"
            # nixfmt: on, as: shell-args
          ]
        }";
      };
    };
  };
}
