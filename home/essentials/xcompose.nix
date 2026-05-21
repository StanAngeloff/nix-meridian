{
  xcompose = {
    enable = true;
    # nixfmt: off
    rules = [
      { include = "%L"; }
      { events = [ "<Multi_key>" "<exclam>" "<equal>" ]; result = { string = "≠"; keysym = "U2260"; }; comment = "NOT EQUAL TO"; }
    ];
    # nixfmt: on
  };
}
