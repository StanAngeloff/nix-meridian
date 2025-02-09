{ pkgs, ... }:
{
  package = pkgs.writeScriptBin "clipboard2markdown" ''
    ${pkgs.xclip}/bin/xclip -sel clip -t text/html -o | \
    ${pkgs.pandoc}/bin/pandoc -f html -t gfm-raw_html --wrap=none
  '';
}
