"""The panel indicator. Sets a label, sets an icon, rebuilds a menu — and nothing else.

Deliberately thin: it holds no state and makes no decisions, so there is nothing here worth a test
that a glance at the panel would not answer faster.
"""

import os

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("AyatanaAppIndicator3", "0.1")

from gi.repository import AyatanaAppIndicator3, Gtk  # noqa: E402

INDICATOR_ID = "claude-usage-tray"

# Our own artwork rather than a name from the icon theme, so the panel shows Claude's starburst
# instead of whichever stock glyph came closest. Absolute paths work because both halves of the
# chain pass them through: libayatana copies the string straight into the IconName property, and the
# appindicator extension treats a leading slash as a file rather than a theme lookup.
#
# Resolved next to this file, which is where the package installs the icons, so the tray also runs
# from a checkout without a build.
_ICON_DIRECTORY = os.path.join(os.path.dirname(os.path.abspath(__file__)), "icons")
FRESH_ICON_PATH = os.path.join(_ICON_DIRECTORY, "claude-symbolic.svg")
STALE_ICON_PATH = os.path.join(_ICON_DIRECTORY, "claude-dim-symbolic.svg")


class Tray:
    def __init__(self, on_refresh, on_quit):
        self._on_refresh = on_refresh
        self._on_quit = on_quit
        self._indicator = AyatanaAppIndicator3.Indicator.new(
            INDICATOR_ID,
            FRESH_ICON_PATH,
            AyatanaAppIndicator3.IndicatorCategory.SYSTEM_SERVICES,
        )
        self._indicator.set_status(AyatanaAppIndicator3.IndicatorStatus.ACTIVE)
        self._indicator.set_title("Claude usage")

    def render(self, label, rows, stale):
        self._indicator.set_label(label, label)
        self._indicator.set_icon_full(
            STALE_ICON_PATH if stale else FRESH_ICON_PATH, "Claude usage"
        )
        self._indicator.set_menu(self._build_menu(rows))

    def repaint(self):
        """Force the shell to repaint a label it cached before it attached to the item.

        The extension caches XAyatanaLabel on attach and refreshes it only from XAyatanaNewLabel,
        which libayatana emits solely when the value changes. So a label set before the shell
        attached stays invisible, and setting the same text again emits nothing to correct it.
        Clearing first guarantees the signal.

        Called once at startup rather than on every render, because clearing makes the extension
        destroy its St.Label and build a new one — churn every poll, on a widget whose styling is
        then resolved after the markup is applied.
        """
        label = self._indicator.get_label()
        self._indicator.set_label("", "")
        self._indicator.set_label(label, label)

    def _build_menu(self, rows):
        menu = Gtk.Menu()
        for row in rows:
            # Insensitive because there is nothing to activate, and a hover highlight on a row that
            # does nothing is a lie. The cost is that the shell renders insensitive text at alpha
            # 0.4, which Pango's foreground attribute cannot compensate for; usage.py's MENU_*
            # colours are pre-brightened for it.
            item = Gtk.MenuItem(label=row)
            item.set_sensitive(False)
            menu.append(item)

        menu.append(Gtk.SeparatorMenuItem())

        refresh_item = Gtk.MenuItem(label="Refresh now")
        refresh_item.connect("activate", lambda _: self._on_refresh())
        menu.append(refresh_item)

        quit_item = Gtk.MenuItem(label="Quit")
        quit_item.connect("activate", lambda _: self._on_quit())
        menu.append(quit_item)

        menu.show_all()
        return menu
