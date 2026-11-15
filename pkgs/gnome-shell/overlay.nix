{ gnome-shell }:
gnome-shell.overrideAttrs (prev: {
  patches = (prev.patches or [ ]) ++ [
    # The message tray shows one banner at a time and queues the rest; only _updateState shows the next one, and it drops
    # any call made while it is already running. A banner that hides without an animation (withdrawn by its app, clicked,
    # closed, or any banner at all when GNOME_SHELL_SLOWDOWN_FACTOR rounds the 200 ms hide down to 0) finishes hiding
    # inside that call, so its request to show the next banner is dropped. The queued notification then waits, visible
    # only in the list behind the clock, until the next notification arrives and shows it in place of the new one.
    #
    # The patch makes a call that arrives mid-run schedule one more run instead of being dropped.
    ./patches/rerun-update-state.patch
  ];
})
