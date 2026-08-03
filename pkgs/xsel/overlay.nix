{ xsel }:
xsel.overrideAttrs (prev: {
  patches = (prev.patches or [ ]) ++ [
    # xsel arms a fatal Xlib error handler as soon as it owns a selection,
    # so a BadWindow from a requestor that has already gone kills it mid-copy and
    # leaves the X11 CLIPBOARD owned by a dead client.
    #
    # Mutter's selection reads carry no timeout, so that pending read never completes and
    # clipboard history extensions stop recording new entries until they are restarted.
    ./patches/survive-vanished-requestor.patch
  ];
})
