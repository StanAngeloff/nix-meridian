{ lib, pkgs, ... }:
{
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;

    package = pkgs.callPackage ./package.nix {
      withFzf = true;
    };
  };

  programs.zsh.initContent =
    let
      zshConfigAfterZoxide =
        lib.mkOrder 2010 # bash
          ''
            # Jump to a directory within the current Git repository.
            function zz() {
                __zoxide_doctor
                \builtin local result
                result="$(\command zoxide query --base-dir="$( git rev-parse --show-toplevel )" -- "$@")" && __zoxide_cd "''${result}"
            }
          '';
    in
    lib.mkMerge [ zshConfigAfterZoxide ];

  # NOTE: To import existing @gsamokovarov/jump data, run:
  #
  # $ cat ~/.config/jump/scores.json | jq -r '.[] | "\(.Path)|\(.Score.Weight)|\(.Score.Age | sub("\\.[0-9]+([+-][0-9]{2}:[0-9]{2}|Z)$"; "Z") | fromdate)"' > z.import
  # $ zoxide import --merge --from z ./z.import
}
