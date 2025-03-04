{
  environment.etc."brave/policies/managed/GroupPolicy.json" = {
    enable = true;
    mode = "0644";
    text = builtins.toJSON {
      "BraveRewardsDisabled" = true;
      "BraveWalletDisabled" = true;
      "BraveVPNDisabled" = true;
      "BraveAIChatEnabled" = false;
    };
  };
}
