{ config, ... }:
let
  binHome = "${config.home.homeDirectory}/.local/bin";
in
{
  # Enable management of XDG base directories.
  xdg.enable = true;

  home.sessionVariables = {
    # https://specifications.freedesktop.org/basedir-spec/latest/#variables
    #
    # > User-specific executable files may be stored in $HOME/.local/bin.
    # > Distributions should ensure this directory shows up in the UNIX $PATH environment variable, at an appropriate place.
    XDG_BIN_HOME = binHome;
  };

  # NOTE: Expressions like $HOME are expanded by the shell.
  home.sessionPath = [ binHome ];

  systemd.user.tmpfiles.rules = [
    # At some point I contemplated extracting "stan" into an option, but let's be real.
    "d \"${binHome}\" 0755 stan users -"
  ];
}
