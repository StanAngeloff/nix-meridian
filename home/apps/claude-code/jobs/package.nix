{
  writeShellApplication,
  coreutils,
  direnv,
  gawk,
  gnused,
  jq,
  libnotify,
  systemd,
  util-linux,
  xdg-utils,
  # The image a job's notifications show.
  icon,
}:
let
  # Same message formatting as the launcher and `cc profiles`, which take their own copy of the library too.
  logHelpers = builtins.readFile ../bubble/utilities/log.sh;
in
writeShellApplication {
  name = "claude-jobs";
  runtimeInputs = [
    coreutils
    direnv
    gawk
    gnused
    jq
    libnotify
    systemd
    util-linux
    xdg-utils
  ];
  text = builtins.replaceStrings [ "@icon@" ] [ "${icon}" ] (
    logHelpers + builtins.readFile ./jobs.sh
  );
}
