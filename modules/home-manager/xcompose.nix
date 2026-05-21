# Salvaged from https://github.com/nix-community/home-manager/pull/2050
# Original author: @bb010g — MIT licensed (same as home-manager)
{ config, lib, ... }:

let
  types = lib.types;
  cfg = config.xcompose;

  nullOptional = x: if x == null then [ ] else [ x ];
  nullMapOptional = f: x: if x == null then [ ] else [ (f x) ];

  concatSpace = lib.concatStringsSep " ";
  concatNewline = lib.concatStringsSep "\n";

  renderEscapedString = str: ''"${lib.replaceStrings [ ''"'' "\n" ] [ ''\"'' "\\n" ] str}"'';
  renderLiteralString = str: renderEscapedString (lib.replaceStrings [ "\\" ] [ "\\\\" ] str);

  includeRuleType = types.submodule (
    { config, lib, ... }:
    {
      options.include = lib.mkOption {
        type = types.nullOr (types.either types.path types.str);
        description = ''
          Path of an existing compose file to include.

          Substitutions (`%H` for home, `%L` for locale compose file,
          `%S` for system locale directory, `%%` for literal `%`) are
          applied to string values but not to path values.
        '';
        default = null;
        example = lib.literalExpression ''"%L"'';
      };

      options.literalInclude = lib.mkOption {
        type = types.nullOr (types.either types.path types.str);
        description = ''
          Path of an existing compose file to include, without
          substitutions. Otherwise identical to `include`.
        '';
        default = null;
      };

      config = lib.mkIf (config.literalInclude != null) {
        include =
          if lib.isString config.literalInclude then
            lib.replaceStrings [ "%" ] [ "%%" ] config.literalInclude
          else
            config.literalInclude;
      };
    }
  );

  renderIncludeRule =
    { include, ... }:
    let
      path =
        if builtins.isPath include then lib.replaceStrings [ "%" ] [ "%%" ] (toString include) else include;
    in
    "include ${renderLiteralString path}";

  sequenceEventType = types.coercedTo types.str (keysym: { inherit keysym; }) (
    types.submodule (
      { lib, ... }:
      {
        options.keysym = lib.mkOption {
          type = types.str;
          description = "Base input keysym.";
        };
        options.exactModifiers = lib.mkOption {
          type = types.bool;
          description = "Whether the modifier list must match exactly.";
          default = false;
        };
        options.modifiers = lib.mkOption {
          type = types.nullOr (types.listOf types.str);
          description = ''
            Modifiers to match with the keysym. Prefix with `~` to require
            absence. Set to `null` to require no modifier.
          '';
          default = [ ];
        };
      }
    )
  );

  renderSequenceEvent =
    {
      keysym,
      modifiers,
      exactModifiers,
      ...
    }:
    if modifiers == null then
      "None"
    else
      concatSpace (lib.optional exactModifiers "!" ++ modifiers ++ [ keysym ]);

  sequenceResultType = types.addCheck (types.submodule (
    { lib, ... }:
    {
      options.string = lib.mkOption {
        type = types.nullOr types.str;
        description = ''
          String produced when the sequence is entered. Can include
          escaped octal (`\123`) or hexadecimal (`\x3a`) codes. If
          omitted, the string is derived from the keysym.
        '';
        default = null;
      };
      options.keysym = lib.mkOption {
        type = types.nullOr types.str;
        description = ''
          Keysym produced when the sequence is entered.
        '';
        default = null;
      };
    }
  )) (result: result.string != null || result.keysym != null);

  renderSequenceResult =
    { string, keysym, ... }:
    concatSpace (nullMapOptional renderEscapedString string ++ nullOptional keysym);

  sequenceRuleType = types.submodule (
    { lib, ... }:
    {
      options.events = lib.mkOption {
        type = types.nonEmptyListOf sequenceEventType;
        description = "Events comprising this compose sequence.";
      };

      options.result = lib.mkOption {
        type = sequenceResultType;
        description = "String, keysym, or both produced by this sequence.";
      };

      options.comment = lib.mkOption {
        type = types.nullOr types.str;
        description = "Trailing inline comment for this compose sequence.";
        default = null;
      };
    }
  );

  renderSequenceRule =
    rule:
    let
      events = builtins.map renderSequenceEvent rule.events;
      result = renderSequenceResult rule.result;
      comment = nullMapOptional (c: "# ${c}") rule.comment;
    in
    concatSpace (
      events
      ++ [
        ":"
        result
      ]
      ++ comment
    );

  commentRuleType = types.submodule (
    { lib, ... }:
    {
      options.comment = lib.mkOption {
        type = types.str;
        description = ''
          A comment or blank line in the resulting compose file. An empty
          string produces a blank line.
        '';
      };
    }
  );

  renderCommentLines =
    lines:
    let
      parts = builtins.split "\n" lines;
      lineCount = lib.length parts / 2 + 1;
    in
    concatNewline (
      builtins.genList (
        i:
        let
          line = lib.elemAt parts (i * 2);
        in
        if line == "" then "#" else "# ${line}"
      ) lineCount
    );

  renderCommentRule = { comment, ... }: if comment == "" then "" else renderCommentLines comment;

  ruleType = types.oneOf [
    (types.addCheck commentRuleType (r: r ? comment && !(r ? events)))
    (types.addCheck includeRuleType (r: r ? include))
    sequenceRuleType
  ];

  renderRule =
    rule:
    (
      if rule ? comment && !(rule ? events) then
        renderCommentRule
      else if rule ? include then
        renderIncludeRule
      else
        renderSequenceRule
    )
      rule;

  renderRules = rules: concatNewline (builtins.map renderRule rules ++ [ "" ]);
in
{
  options.xcompose = {
    enable = lib.mkEnableOption "XCompose configuration";
    rules = lib.mkOption {
      type = types.listOf ruleType;
      default = [ ];
      description = ''
        User compose rules. Each element is either an include rule,
        a comment, or a compose sequence with events and a result.
      '';
    };
    rulesText = lib.mkOption {
      type = types.lines;
      description = ''
        Raw compose rules text. Setting this overrides any
        auto-generated text from `rules`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    xcompose.rulesText = lib.mkDefault (renderRules cfg.rules);
    home.file.".XCompose".text = cfg.rulesText;
  };
}
