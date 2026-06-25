{ pkgs, ... }:
{
  services.pcscd.enable = true;

  # Register OpenSC with p11-kit so browsers can discover the token via the proxy.
  # onepin variant avoids double-PIN prompts on single-PIN cards like the InfoNotary card.
  environment.etc."pkcs11/modules/opensc-pkcs11".text =
    "module: ${pkgs.opensc}/lib/onepin-opensc-pkcs11.so\n";

  environment.systemPackages = with pkgs; [
    opensc
    p11-kit
    pcsc-tools
    nssTools
  ];
}
