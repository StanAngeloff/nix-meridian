{
  lib,
  writeShellApplication,
  name ? "voxinput-record",
  icon ? "microphone-sensitivity-high",
  replaceVars,
  voxinput,
  dotool,
  libnotify,
  procps,
  systemd,
  tmux,
  zenity,
}:
writeShellApplication {
  inherit name;

  text = builtins.readFile (
    replaceVars ./record.sh {
      inherit name icon;

      voxinput = lib.getExe voxinput;

      busctl = "${lib.getBin systemd}/bin/busctl";
      dotool = "${lib.getBin dotool}/bin/dotool";
      notify-send = lib.getExe libnotify;
      pgrep = "${lib.getBin procps}/bin/pgrep";
      tmux = lib.getExe tmux;
      zenity = lib.getExe zenity;
    }
  );

  meta.mainProgram = name;
}
