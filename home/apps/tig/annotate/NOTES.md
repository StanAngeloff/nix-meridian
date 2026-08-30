# annotation-marks.patch — development notes

Patch for tig that renders a ※ (U+203B REFERENCE MARK) on diff lines that have a tig-annotate annotation file, and on status view files that have any annotation at any line.

## Architecture

The patch touches four files in the tig source:

| File                 | What                                                                                                               |
| -------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `include/tig/line.h` | Adds `LINE_ANNOTATION_MARK` color type                                                                             |
| `include/tig/diff.h` | Declares `annotations_scan`, `annotations_exist`, `annotations_has`, `annotations_has_file` |
| `src/diff.c`         | Annotation directory scanning and lookup                                                                           |
| `src/draw.c`         | Mark rendering in `draw_view_line()`, scan triggers in `redraw_view_from()` and `redraw_view_dirty()`              |

### How annotation files are named

The companion shell script (`tig-annotate.sh`) stores one `.md` file per annotation in `{git_dir}/tig-annotate/`. Filenames follow the pattern:

    {encoded_path}:{lineno}.md

where `/` in the path is replaced with U+00B7 MIDDLE DOT (UTF-8: `C2 B7`), and `lineno` is either a decimal line number or the literal string `file` for file-level annotations (on diff headers before the first `@@`).

The C code in `annotations_scan()` reads this directory and caches the filenames (stripped of `.md`) as lookup keys. `annotations_has()` encodes the path the same way and does a linear scan of the cache.

### Scan and refresh strategy

- `annotations_scan()` is called from `redraw_view_from()` (covers full redraws) and `redraw_view_dirty()` (covers cursor movement).
- A `stat()` on the annotation directory gates the actual `opendir`/`readdir` rescan — only happens when `st_mtime` or `st_ctime` changes. Scrolling costs one `stat()`, not a directory listing.

### Line type handling

| Line type                             | Lineno source                                               | Selected?                     |
| ------------------------------------- | ----------------------------------------------------------- | ----------------------------- |
| `LINE_DIFF_ADD`, `LINE_DIFF_ADD2`     | new-file (`old=false`)                                      | shown (inherits cursor color) |
| `LINE_DIFF_DEL`, `LINE_DIFF_DEL2`     | old-file (`old=true`)                                       | shown (inherits cursor color) |
| `LINE_DEFAULT` (context in chunk)     | new-file (`old=false`), skip if `diff_get_lineno` returns 0 | shown (inherits cursor color) |
| `LINE_DIFF_HEADER`                    | file-level (`lineno=0` maps to key `{path}:file`)           | shown (inherits cursor color) |
| `LINE_STAT_STAGED/UNSTAGED/UNTRACKED` | `annotations_has_file()` prefix match                       | shown (inherits cursor color) |

The DEL-line old-file lookup matches `tig-annotate.sh`'s fallback logic: `%(lineno)` first, then `%(lineno_old)` when the new-file lineno is 0.

### Rendering details

- The mark is drawn after `view->ops->draw()` returns, in `draw_view_line()`.
- Position comes from `getyx()` (cursor after the draw callback).
- Status view: rewinds past column field padding via `mvwinch` backward scan.
- Overflow: if cursor is past `max_x - 2`, clamp to `max_x - 2` (overlays text).
- Color: `LINE_ANNOTATION_MARK`, configured in `bindings.tigrc` as `color annotation-mark color214 default` (orange).

## Rebuilding the patch

When tig updates (for example, 2.6.1 to 3.0), the patch will likely fail to apply. Rebuild it as follows:

```bash
# 1. Get the new tig source
new_src=$(nix build nixpkgs#tig.src --print-out-paths --no-link)

# 2. Make two copies: "original" (with existing patches) and "working"
cp -r "$new_src" /tmp/tig-orig && chmod -R u+w /tmp/tig-orig
cp -r "$new_src" /tmp/tig-src  && chmod -R u+w /tmp/tig-src

# 3. Apply the OTHER patches (not annotation-marks) to both copies
for p in pkgs/tig/patches/*.patch; do
  [[ "$p" == *annotation-marks* ]] && continue
  patch -d /tmp/tig-orig -p1 < "$p"
  patch -d /tmp/tig-src  -p1 < "$p"
done

# 4. Port the changes to the working copy.
#    Read the old patch for intent, then edit the four files in /tmp/tig-src/:
#      include/tig/line.h   — add _(ANNOTATION_MARK, "") near DIFF_HEADER_FILL
#      include/tig/diff.h   — add function declarations before "extern struct view diff_view"
#      src/diff.c           — add #include <dirent.h>, #include <sys/stat.h>,
#                             and the annotation functions before diff_ops
#      src/draw.c           — add #include "tig/diff.h", #include "tig/status.h",
#                             annotation block after the diff-line-fill block in
#                             draw_view_line(), scan calls in redraw_view_from()
#                             and redraw_view_dirty()

# 5. Generate the new patch
for f in include/tig/diff.h include/tig/line.h src/diff.c src/draw.c; do
  diff -ruN "/tmp/tig-orig/$f" "/tmp/tig-src/$f" \
    --label "i/$f" --label "w/$f" || true
done > pkgs/tig/patches/annotation-marks.patch

# 6. Build and verify
nix build .#nixosConfigurations.$(hostname).pkgs.tig
```

## Testing checklist

All tests assume `make switch` has been run.

### Diff/pager view

1. Open tig on a repo with existing annotations (`git diff | tig` or Ctrl-G).
2. **Annotated +/- lines** show ※ after the text (orange, `color214`).
3. **Context lines** (no +/-) with annotations also show ※.
4. **File-level annotations** (on `diff --git` header lines) show ※.
5. **Selected line** (cursor) shows ※ in cursor color (inherits highlight, no color clash).
6. **Long lines** that overflow the screen edge: ※ appears at the right edge, overlaying text.

### Immediate refresh

7. Press `cn` on an unannotated line, type a note, press Esc. The ※ should appear **immediately** without moving the cursor.
8. Press `cn` on an annotated line, delete all text, press Esc. The ※ should disappear immediately.

### Status view

9. Press `s` to open the status view. Files that have any annotation show ※ after the filename.
10. The ※ shows on the **selected line** too (inheriting the cursor color).
11. After adding/removing an annotation and returning to the status view, the ※ updates.

### Split view

12. In split view (diff + status), both panes show ※ marks.
13. Adding an annotation in the diff pane updates the status pane's ※.

### Navigating away and back

14. From the pager, press Enter to open a sub-view, then press `q` to return. The ※ marks should still be visible (not lost on view transition).

## Gotchas learned the hard way

- **Never skip drawing the mark on selected lines.** `draw_view_line()` sets `line->selected` before calling the draw callback, but `view->ops->draw()` only writes the text — it does not clear the remainder of the row. If you skip the mark on selected lines, the previous paint's mark stays in the ncurses window buffer as a ghost. Any `werase()` (Ctrl-L, view reopen, maximize) clears the ghost, and the mark is never redrawn. The fix: always draw the mark, but skip `wattrset` on selected lines so it inherits the cursor color.
- **ncurses `TRUE` vs `true`**: tig's build does not define `TRUE`; use C99 `true` (from `stdbool.h`, pulled in by tig headers).
- **Status view field padding**: `draw_filename()` pads to column width. After the draw callback, the cursor is at the field end, not the text end. Walk backward with `mvwinch` to find the last non-space character.
- **`diff_get_lineno()` for `LINE_DEFAULT`**: returns 0 if the line is not inside a diff chunk (for example, commit message lines). Must guard on this to avoid false matches.
- **Path encoding**: `\xc2\xb7` is U+00B7 MIDDLE DOT in UTF-8. Must match the `sed 's|/|·|g'` in `tig-annotate.sh`.
- **`diff` exit code**: `diff -ruN` returns 1 when files differ (not an error). Chain patch generation with `|| true`, not `&&`.
- **Nix flake visibility**: new patch files need `git add --intent-to-add` before `nix build` can see them.
- **`strndup`**: tig provides a compat shim (`compat/strndup.o`) via `configure.ac` — safe to use.
