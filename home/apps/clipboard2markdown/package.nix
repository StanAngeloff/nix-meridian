{
  writeShellScriptBin,
  xclip,
  pandoc,
}:
writeShellScriptBin "clipboard2markdown" ''
  ${xclip}/bin/xclip -sel clip -t text/html -o | \
  ${pandoc}/bin/pandoc -f html -t gfm-raw_html --wrap=none
''
