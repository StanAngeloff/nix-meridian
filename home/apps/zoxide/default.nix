{ lib, pkgs-unstable, ... }:
{
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;

    package = pkgs-unstable.zoxide.override {
      withFzf = true;
    };
  };

  programs.zsh.initContent =
    let
      zshConfigAfterZoxide = lib.mkOrder 2010 ''
        source ${./zz.zsh}
      '';
    in
    lib.mkMerge [ zshConfigAfterZoxide ];

  # NOTE: To import existing @gsamokovarov/jump data, run:
  #
  # $ cat ~/.config/jump/scores.json | jq -r '.[] | "\(.Path)|\(.Score.Weight)|\(.Score.Age | sub("\\.[0-9]+([+-][0-9]{2}:[0-9]{2}|Z)$"; "Z") | fromdate)"' > z.import
  # $ zoxide import --merge --from z ./z.import
}
