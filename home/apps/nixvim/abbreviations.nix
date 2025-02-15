{ lib, ... }:
let
  abbreviations = {
    "anohter" = "another";
    "antoher" = "another";
    "aray" = "array";
    "continious" = "continuous";
    "eixt" = "exit";
    "froeach" = "foreach";
    "isntance" = "instance";
    "naem" = "name";
    "otehrwise" = "otherwise";
    "overriden" = "overridden";
    "parma" = "param";
    "pritn" = "print";
    "retrun" = "return";
    "reutrn" = "return";
    "srting" = "string";
    "udnefined" = "undefined";
    "vlaue" = "value";
  };
in
{
  programs.nixvim.extraConfigVim = ''
    ${builtins.concatStringsSep "\n" (
      lib.mapAttrsToList (key: value: "iabbrev ${key} ${value}") abbreviations
    )}
  '';
}
