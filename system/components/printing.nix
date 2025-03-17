{
  # Enable CUPS to print documents.
  #
  # Learn more at https://nixos.wiki/wiki/Printing#Installation
  services.printing = {
    enable = true;
  };

  # Learn more at https://nixos.wiki/wiki/Printing#Enable_autodiscovery_of_network_printers
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };
}
