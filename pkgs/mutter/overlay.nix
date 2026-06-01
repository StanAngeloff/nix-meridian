{ mutter }:
mutter.overrideAttrs (prev: {
  patches = (prev.patches or [ ]) ++ [
    # Mutter 50 server-side key repeat (wl_keyboard v10) stops repeating when any other key is released.
    # https://gitlab.gnome.org/GNOME/mutter/-/issues/4675
    ./patches/gnome-mutter-4675-prevent-modifier-release-from-stopping-key-repeat.patch
  ];
})
