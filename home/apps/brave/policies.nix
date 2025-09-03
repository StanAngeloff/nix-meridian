{
  environment.etc."brave/policies/managed/GroupPolicy.json" = {
    enable = true;
    mode = "0644";
    text = builtins.toJSON {
      # Learn more at https://support.brave.app/hc/en-us/articles/360039248271-Group-Policy
      "TorDisabled" = true;
      "BraveRewardsDisabled" = true;
      "BraveWalletDisabled" = true;
      "BraveVPNDisabled" = true;
      "BraveAIChatEnabled" = false;
      "BraveNewsDisabled" = true;
      "BraveTalkDisabled" = true;
    };
  };
}
