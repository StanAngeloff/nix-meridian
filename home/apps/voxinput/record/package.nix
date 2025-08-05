{
  lib,
  writeShellApplication,
  name ? "voxinput-record",
  icon ? "microphone-sensitivity-high",
  replaceVars,
  libnotify,
  voxinput,
  zenity,
}:
writeShellApplication {
  inherit name;

  text = builtins.readFile (
    replaceVars ./record.sh {
      inherit name icon;

      voxinput = "${lib.makeBinPath [ voxinput ]}/voxinput";
      zenity = "${lib.makeBinPath [ zenity ]}/zenity";
      notify-send = "${lib.makeBinPath [ libnotify ]}/notify-send";
    }
  );
}
