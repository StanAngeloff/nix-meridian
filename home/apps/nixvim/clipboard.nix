{
  # Route Neovim's clipboard through xsel rather than wl-clipboard on this GNOME/Wayland session.
  #
  # GNOME/Mutter implements neither wlr-data-control nor ext-data-control, so wl-copy/wl-paste cannot reach the selection headlessly:
  # they open an invisible surface and wait for keyboard focus, which Mutter's focus-stealing prevention withholds while you are typing.
  # Neovim then blocks on the pending wl-paste — in practice yanky's sync_with_ring read on FocusGained — and that stall is the editor "freeze".
  #
  # xsel reads and writes the X11 CLIPBOARD through the already-running XWayland; X11 selection ownership needs no focus,
  # and Mutter mirrors that clipboard to and from the Wayland one both ways, so copy and paste keep working without the stall.
  programs.nixvim = {
    clipboard.providers.xsel.enable = true;

    # providers.xsel only adds xsel to Neovim's PATH; Neovim's own detection still prefers wl-copy
    # whenever $WAYLAND_DISPLAY is set (autoload/provider/clipboard.vim), so pin the provider explicitly.
    globals.clipboard = "xsel";
  };
}
