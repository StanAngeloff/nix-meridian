{
  programs.nixvim.extraConfigLua = ''
    ${builtins.readFile ./commands/sort.lua}
    ${builtins.readFile ./commands/trash.lua}
  '';
}
