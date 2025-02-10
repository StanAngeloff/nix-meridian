{
  fonts = {
    enableDefaultPackages = true;

    fontconfig = {
      enable = true;

      # This would ideally be done in Home Manager, however it lacks the option to add extra configuration.
      localConf = ''
        <alias>
          <family>Segoe UI</family>
          <prefer>
            <family>Segoe UI Variable</family>
          </prefer>
        </alias>
      '';
    };
  };
}
