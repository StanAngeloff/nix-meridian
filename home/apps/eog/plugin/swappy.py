import os
import re
import subprocess
import sys
import time
import traceback

LOG = os.path.expanduser("~/.local/state/eog-swappy-plugin/probe.log")
SWAPPY = "@swappy@"

try:
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
except Exception:
    pass


def _log(msg):
    line = f"[{time.strftime('%H:%M:%S')}] {msg}"
    try:
        with open(LOG, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass
    print(line, file=sys.stderr, flush=True)


_log("=" * 60)
_log(f"module import start; python={sys.version.split()[0]} exe={sys.executable}")
_log(f"sys.path entries: {len(sys.path)}")

try:
    import gi

    _log(f"imported gi from {gi.__file__}")
except Exception as e:
    _log(f"FAIL import gi: {e}")
    _log(traceback.format_exc())
    raise

try:
    eog_exe = os.path.realpath("/proc/self/exe")
    eog_prefix = os.path.dirname(os.path.dirname(eog_exe))
    eog_gir = os.path.join(eog_prefix, "lib", "eog", "girepository-1.0")
    _log(f"eog_exe={eog_exe} eog_gir={eog_gir} exists={os.path.isdir(eog_gir)}")
    from gi.repository import GIRepository

    GIRepository.Repository.dup_default().prepend_search_path(eog_gir)
    _log("prepended eog gir to GIRepository search path")
except Exception as e:
    _log(f"FAIL prepend gir path: {e}")
    _log(traceback.format_exc())
    raise

try:
    gi.require_version("GObject", "2.0")
    gi.require_version("Gtk", "3.0")
    gi.require_version("Eog", "3.0")
    _log("require_version ok for GObject/Gtk/Eog")
except Exception as e:
    _log(f"FAIL require_version: {e}")
    _log(traceback.format_exc())
    raise

from gi.repository import GObject, Gio, Gtk, Eog  # noqa: E402

_log("imported gi.repository modules successfully")


def _reserve_output_path(source):
    base, _ = os.path.splitext(source)
    base = re.sub(r"( \(\d+\))?\.o$", "", base)
    candidate = f"{base}.o.png"
    n = 2
    while True:
        try:
            open(candidate, "x").close()
            return candidate
        except FileExistsError:
            candidate = f"{base} ({n}).o.png"
            n += 1
            if n > 9999:
                raise RuntimeError(f"too many .o variants for {source}")


def _find_headerbar(widget, depth=0):
    if widget is None or depth > 12:
        return None
    if type(widget).__name__ == "HdyHeaderBar":
        return widget
    if hasattr(widget, "get_children"):
        for child in widget.get_children():
            found = _find_headerbar(child, depth + 1)
            if found is not None:
                return found
    return None


class SwappyPlugin(GObject.Object, Eog.WindowActivatable):
    __gtype_name__ = "SwappyPlugin"
    window = GObject.Property(type=Eog.Window)

    def do_activate(self):
        _log(f"do_activate called on window={self.window!r}")
        action = Gio.SimpleAction.new("swappy-edit", None)
        action.connect("activate", self._on_edit)
        self.window.add_action(action)

        app = self.window.get_application()
        if app is not None:
            app.set_accels_for_action("win.swappy-edit", ["<Primary>e"])
            _log("bound Ctrl+E to win.swappy-edit")
        else:
            _log("WARN: get_application() returned None, no accel bound")

        self._button = Gtk.Button.new_from_icon_name(
            "document-edit-symbolic", Gtk.IconSize.BUTTON
        )
        self._button.set_tooltip_text("Edit in Swappy (Ctrl+E)")
        self._button.set_action_name("win.swappy-edit")
        self._button.show()

        headerbar = _find_headerbar(self.window)
        _log(f"found headerbar: {type(headerbar).__name__ if headerbar else None}")
        if headerbar is not None:
            try:
                headerbar.add(self._button)
                _log("added button to headerbar")
            except Exception as e:
                _log(f"FAIL add button: {e}")
                self._button = None
        else:
            self._button = None
            _log("WARN: no headerbar found; button not attached")

    def do_deactivate(self):
        _log("do_deactivate called")
        self.window.remove_action("swappy-edit")
        button = getattr(self, "_button", None)
        if button is not None:
            parent = button.get_parent()
            if parent is not None:
                parent.remove(button)
            self._button = None

    def _on_edit(self, action, param):
        image = self.window.get_image()
        if image is None:
            _log("action fired but window has no image")
            return
        gfile = image.get_file()
        path = gfile.get_path() if gfile is not None else None
        _log(f"action fired; image path={path!r}")
        if not path:
            return
        try:
            output = _reserve_output_path(path)
        except Exception as e:
            _log(f"FAIL reserve output: {e}")
            _log(traceback.format_exc())
            return
        try:
            subprocess.Popen([SWAPPY, "-f", path, "-o", output], start_new_session=True)
            _log(f"launched swappy with output={output}")
        except Exception as e:
            _log(f"FAIL launch swappy: {e}")
            _log(traceback.format_exc())
            try:
                os.unlink(output)
            except OSError:
                pass


_log("class SwappyPlugin defined; module import end")
