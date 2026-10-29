"""Renders both sides of a single-file image diff for tig's stage view.

tig runs this helper when its stage view shows one binary or Git LFS file.
`prepare` reads both sides, shrinks them to panel size and writes raw RGBA pixel files,
which tig hands to the terminal through the kitty graphics protocol.
`tint` redraws the new side with its changed pixels tinted at another opacity, and `cleanup` removes the cache.

Each tig keeps its cache in $XDG_RUNTIME_DIR/tig-image-diff/<pid> and holds an exclusive lock on <pid>.lock beside it until it exits.

Every answer is one fact per line, which tig parses:

    old <width> <height> <path>    raw RGBA pixels of the old side, when it exists
    new <width> <height> <path>    raw RGBA pixels of the new side, when it exists
    mask                           both sides have the same size, so `tint` can highlight changes
    note <text>                    a message for tig's status bar
    skip <text>                    not an image, so tig keeps quiet; printed with a non-zero exit status
    error <text>                   printed with a non-zero exit status
"""

import argparse
import fcntl
import os
import shutil
import subprocess
import sys
from pathlib import Path

# The terminal scales each panel into the cells it gets, so larger panels only cost time.
PANEL_LIMIT = 1600
SOURCE_LIMIT = 64 * 1024 * 1024
# Formats ImageMagick recognises by their bytes alone; the source files carry no extension.
FORMATS = {
    "PNG",
    "JPEG",
    "GIF",
    "WEBP",
    "BMP",
    "TIFF",
    "AVIF",
    "HEIC",
    "JXL",
    "PSD",
    "QOI",
}
TINT_COLOR = "rgb(255,0,255)"
CACHE_PARENT_NAME = "tig-image-diff"


class Refusal(Exception):
    """A diff this helper will not render; tig keeps showing the plain text and reports why."""


class Skip(Refusal):
    """A binary file that is not an image, which is no news."""


def is_absent(revision):
    return revision == "" or set(revision) == {"0"}


def copy_limited(source, destination_file):
    copied = 0
    while chunk := source.read(1024 * 1024):
        copied += len(chunk)
        if copied > SOURCE_LIMIT:
            raise Refusal(f"larger than {SOURCE_LIMIT // (1024 * 1024)} MiB")
        destination_file.write(chunk)


def write_side(path, revision, destination_path):
    """Writes one side's bytes to destination_path; False when that side does not exist."""
    if revision == "worktree":
        try:
            with open(path, "rb") as source, open(
                destination_path, "wb"
            ) as destination_file:
                copy_limited(source, destination_file)
        except FileNotFoundError:
            return False
        return True

    if is_absent(revision):
        return False

    # --filters runs the smudge filter, which turns a Git LFS pointer into the real image.
    with subprocess.Popen(
        ["git", "cat-file", "--filters", f"--path={path}", revision],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    ) as process:
        try:
            with open(destination_path, "wb") as destination_file:
                copy_limited(process.stdout, destination_file)
        except Refusal:
            process.kill()
            raise
        error_output = process.stderr.read().decode(errors="replace").strip()
    if process.returncode != 0:
        raise Refusal(
            f"git cat-file failed: {error_output.splitlines()[0] if error_output else revision}"
        )
    return True


def magick(*arguments):
    result = subprocess.run(["magick", *arguments], capture_output=True, text=True)
    if result.returncode != 0:
        message = result.stderr.strip().splitlines()
        raise Refusal(f"ImageMagick failed: {message[0] if message else 'no output'}")
    return result.stdout


def identify(source_path):
    """Returns (width, height) of the first frame, or None when it is not an image format we render."""
    result = subprocess.run(
        ["magick", "identify", "-format", "%m %w %h\n", f"{source_path}[0]"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0 or not result.stdout.strip():
        return None
    image_format, width, height = result.stdout.splitlines()[0].split()
    if image_format not in FORMATS:
        return None
    return int(width), int(height)


def replace_atomically(temporary_path, final_path):
    # The terminal reads pixel files on its own schedule, so it must never see a half-written one.
    os.replace(temporary_path, final_path)


def write_panel(source_path, cache_path, name):
    """Shrinks the first frame to panel size; returns (width, height, raw RGBA path)."""
    raw_path = cache_path / f"{name}.rgba"
    temporary_path = cache_path / f"{name}.rgba.tmp"
    dimensions = magick(
        f"{source_path}[0]",
        "-auto-orient",
        "-resize",
        f"{PANEL_LIMIT}x{PANEL_LIMIT}>",
        "-colorspace",
        "sRGB",
        "-depth",
        "8",
        "-write",
        str(cache_path / f"{name}.mpc"),
        "-write",
        f"RGBA:{temporary_path}",
        "-format",
        "%w %h",
        "info:",
    )
    replace_atomically(temporary_path, raw_path)
    width, height = dimensions.split()
    return int(width), int(height), raw_path


def write_mask(old_source_path, new_source_path, cache_path, width, height):
    """Marks every changed pixel white at full size, then scales the mask to the panel; returns the changed percentage."""
    full_mask_path = cache_path / "mask-full.mpc"
    result = subprocess.run(
        [
            "magick",
            "compare",
            "-metric",
            "AE",
            "-highlight-color",
            "white",
            "-lowlight-color",
            "black",
            "-compose",
            "src",
            f"{old_source_path}[0]",
            f"{new_source_path}[0]",
            str(full_mask_path),
        ],
        capture_output=True,
        text=True,
    )
    # compare exits 1 when the images differ, which is the usual case here.
    if result.returncode not in (0, 1):
        message = result.stderr.strip().splitlines()
        raise Refusal(
            f"ImageMagick compare failed: {message[0] if message else 'no output'}"
        )
    # A box filter keeps a single changed pixel visible after shrinking: any changed pixel in a block marks the block.
    percentage = magick(
        str(full_mask_path),
        "-alpha",
        "off",
        "-colorspace",
        "gray",
        "-format",
        "%[fx:mean*100]",
        "-write",
        "info:",
        "-scale",
        f"{width}x{height}!",
        "-threshold",
        "0",
        str(cache_path / "mask.mpc"),
    )
    return float(percentage)


def tint(cache_path, opacity):
    """Rewrites new.rgba with the changed pixels tinted at opacity percent."""
    raw_path = cache_path / "new.rgba"
    temporary_path = cache_path / "new.rgba.tmp"
    dimensions = magick(
        str(cache_path / "new.mpc"),
        "(",
        str(cache_path / "mask.mpc"),
        "-background",
        TINT_COLOR,
        "-alpha",
        "shape",
        "-channel",
        "A",
        "-evaluate",
        "multiply",
        f"{opacity / 100:.2f}",
        "+channel",
        ")",
        "-compose",
        "over",
        "-composite",
        "-depth",
        "8",
        "-write",
        f"RGBA:{temporary_path}",
        "-format",
        "%w %h",
        "info:",
    )
    replace_atomically(temporary_path, raw_path)
    width, height = dimensions.split()
    return int(width), int(height), raw_path


def checked_cache_path(cache):
    # tig names the cache $XDG_RUNTIME_DIR/tig-image-diff/<pid>; refusing anything else keeps cleanup's rmtree contained.
    cache_path = Path(cache)
    if not cache_path.name.isdigit() or cache_path.parent.name != CACHE_PARENT_NAME:
        raise Refusal(f"unexpected cache directory: {cache}")
    return cache_path


def lock_path_of(cache_path):
    return cache_path.with_name(f"{cache_path.name}.lock")


def sweep_abandoned(cache_path):
    """Removes the caches of tig processes that died without running cleanup, as when their tmux pane closed.

    A lock this helper can take belongs to a tig that is gone; locks also work across PID namespaces, where process ids do not.
    """
    names = {path.name.removesuffix(".lock") for path in cache_path.parent.iterdir()}
    for name in names:
        if not name.isdigit() or name == cache_path.name:
            continue
        sibling_path = cache_path.parent / name
        try:
            with open(lock_path_of(sibling_path), "rb") as lock_file:
                fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
                shutil.rmtree(sibling_path, ignore_errors=True)
                lock_path_of(sibling_path).unlink()
        except FileNotFoundError:
            shutil.rmtree(sibling_path, ignore_errors=True)
        except BlockingIOError:
            continue


def format_percentage(percentage):
    if percentage == 0:
        return "no pixels changed"
    if percentage < 0.01:
        return "under 0.01% of pixels changed"
    return f"{percentage:.2f}% of pixels changed"


def prepare(arguments):
    cache_path = checked_cache_path(arguments.cache)
    shutil.rmtree(cache_path, ignore_errors=True)
    cache_path.mkdir(parents=True)
    sweep_abandoned(cache_path)

    sources = {}
    for name, path, revision in (
        ("old", arguments.old_path or arguments.path, arguments.old),
        ("new", arguments.path, arguments.new),
    ):
        source_path = cache_path / f"{name}.source"
        if not write_side(path, revision, source_path):
            continue
        dimensions = identify(source_path)
        if dimensions is None:
            raise Skip("not an image")
        sources[name] = (source_path, dimensions)

    if not sources:
        raise Refusal("neither side exists")

    panels = {
        name: write_panel(source_path, cache_path, name)
        for name, (source_path, _) in sources.items()
    }
    has_mask = False

    if len(sources) == 1:
        name = next(iter(sources))
        width, height = sources[name][1]
        note = f"{'deleted' if name == 'old' else 'new'} image, {width}x{height}"
    elif sources["old"][1] != sources["new"][1]:
        (old_width, old_height), (new_width, new_height) = (
            sources["old"][1],
            sources["new"][1],
        )
        note = f"size changed: {old_width}x{old_height} → {new_width}x{new_height}"
    else:
        width, height, _ = panels["new"]
        percentage = write_mask(
            sources["old"][0], sources["new"][0], cache_path, width, height
        )
        panels["new"] = tint(cache_path, arguments.opacity)
        has_mask = True
        note = format_percentage(percentage)

    for name, (width, height, raw_path) in panels.items():
        print(f"{name} {width} {height} {raw_path}")
    if has_mask:
        print("mask")
    print(f"note {note}")


def retint(arguments):
    cache_path = checked_cache_path(arguments.cache)
    if not (cache_path / "mask.mpc").exists():
        raise Refusal("no highlight for this diff")
    width, height, raw_path = tint(cache_path, arguments.opacity)
    print(f"new {width} {height} {raw_path}")


def cleanup(arguments):
    cache_path = checked_cache_path(arguments.cache)
    shutil.rmtree(cache_path, ignore_errors=True)
    lock_path_of(cache_path).unlink(missing_ok=True)


def opacity_percent(value):
    opacity = int(value)
    if not 0 <= opacity <= 100:
        raise argparse.ArgumentTypeError("opacity is a percentage from 0 to 100")
    return opacity


def parse_arguments(argv):
    parser = argparse.ArgumentParser(prog="tig-image-diff")
    commands = parser.add_subparsers(dest="command", required=True)

    prepare_parser = commands.add_parser("prepare")
    prepare_parser.add_argument("--cache", required=True)
    prepare_parser.add_argument("--path", required=True)
    prepare_parser.add_argument(
        "--old-path", help="the old side's path when the file was renamed"
    )
    prepare_parser.add_argument(
        "--old",
        required=True,
        help="blob id; all zeros when the old side does not exist",
    )
    prepare_parser.add_argument(
        "--new", required=True, help="blob id, all zeros, or worktree"
    )
    prepare_parser.add_argument("--opacity", type=opacity_percent, required=True)

    tint_parser = commands.add_parser("tint")
    tint_parser.add_argument("--cache", required=True)
    tint_parser.add_argument("--opacity", type=opacity_percent, required=True)

    cleanup_parser = commands.add_parser("cleanup")
    cleanup_parser.add_argument("--cache", required=True)

    return parser.parse_args(argv)


def main(argv):
    arguments = parse_arguments(argv)
    command = {"prepare": prepare, "tint": retint, "cleanup": cleanup}[
        arguments.command
    ]
    try:
        command(arguments)
    except Skip as skip:
        print(f"skip {skip}")
        return 1
    except Refusal as refusal:
        print(f"error {refusal}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
