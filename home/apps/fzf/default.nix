{
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;

    colors = {
      prompt = "244";
      pointer = "244";
      marker = "201";
    };

    defaultOptions = let
      bindOptions = {
        "ctrl-f" = "page-down";
        "ctrl-b" = "page-up";
        "ctrl-d" = "half-page-down";
        "ctrl-u" = "half-page-up";
      };
      bindOptionsAsString = builtins.concatStringsSep "," (
        builtins.attrValues (
          builtins.mapAttrs (key: value: "${key}:${value}") bindOptions
        )
      );
    in [
      "--color=bw"
      "--layout=reverse"
      "--info=inline"
      "--no-separator"
      "--prompt='→ '"
      "--marker='×'"
      "--pointer='▶'"
      "--ellipsis='…'"
      "--bind '${bindOptionsAsString}'"
    ];
  };
}
