{
  writeShellApplication,
  makeDesktopItem,
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

  # The app every job notification names with the desktop-entry hint, Claude Code jobs with the tray's icon.
  desktopEntry = "claude-jobs";
  desktopItem = makeDesktopItem {
    name = desktopEntry;
    desktopName = "Claude Code jobs";
    comment = "Notifications from scheduled Claude Code jobs";
    icon = "${icon}";
    # The notifications are the only way in, so there is nothing to launch from the app grid.
    noDisplay = true;
    # An application entry needs a command, and this one has nothing to do.
    exec = "true";
  };
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
  text = builtins.replaceStrings [ "@icon@" "@desktopEntry@" ] [ "${icon}" desktopEntry ] (
    logHelpers + builtins.readFile ./jobs.sh
  );
  passthru = { inherit desktopItem; };
}
