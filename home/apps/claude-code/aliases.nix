{ lib, claude-code }:
let
  args = [
    "--effort"
    "max"
  ]
  ++ [
    "--model"
    "claude-opus-4-6[1m]"
  ];
  argsStr = lib.strings.concatMapStringsSep " " (
    s: if lib.strings.hasPrefix "-" s then s else lib.strings.escapeShellArg s
  ) args;
in
{
  programs.zsh.shellAliases = {
    cc = "${lib.getExe claude-code} ${argsStr}";
    ccc = "${lib.getExe claude-code} ${argsStr} --dangerously-skip-permissions";
  };
}
