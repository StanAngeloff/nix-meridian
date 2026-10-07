# annotation-marks.patch — development notes

Patch for tig that exposes the selected diff line's annotation key as `%(annotation)` and renders a ※ (U+203B REFERENCE MARK) on diff lines that have a note, and on status view files that have any note at any line.

## Architecture

The patch touches six files in the tig source:

| File                 | What                                                                                                              |
| -------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `include/tig/argv.h` | Adds the `annotation` state variable (`%(annotation)`) to `ARGV_ENV_INFO`                                         |
| `include/tig/line.h` | Adds `LINE_ANNOTATION_MARK` color type                                                                            |
| `include/tig/diff.h` | Declares `annotations_scan`, `annotations_exist`, `annotation_key`, `annotations_has_key`, `annotations_has_file` |
| `src/diff.c`         | `annotation_key()` and `annotation_old_pathname()`, annotation directory scanning and lookup                      |
| `src/pager.c`        | `pager_select()` fills `%(annotation)` through `annotation_key()`                                                 |
| `src/draw.c`         | Mark rendering in `draw_view_line()`, scan triggers in `redraw_view_from()` and `redraw_view_dirty()`             |

The store itself belongs to `tig-annotate-store` (`store.py`): it names notes, writes sidecars, and exports. `tig-annotate.sh` only handles the tmux popup, fzf, and notifications.

### Annotation keys

`annotation_key()` in `src/diff.c` is the single source of truth. `pager_select()` stores its result in `%(annotation)` for the bindings, and `draw_view_line()` uses it to look marks up, so a note and its mark cannot disagree.

| Line type                         | Key                                  |
| --------------------------------- | ------------------------------------ |
| `LINE_DIFF_ADD`, `LINE_DIFF_ADD2` | `{path}:{lineno}` (new-file number)  |
| `LINE_DEFAULT` inside a chunk     | `{path}:{lineno}` (new-file number)  |
| `LINE_DIFF_DEL`, `LINE_DIFF_DEL2` | `{path}:-{lineno}` (old-file number) |
| anything else                     | none: `%(annotation)` is empty       |

"Inside a chunk" means `diff_get_lineno()` returns more than 0; it returns 0 for commit messages, diffstat, and headers. `\ No newline at end of file` has its own line type. The path is the new-side name, or the old-side name when the new side is `/dev/null` (a deleted file). tig strips only the `a/`, `b/`, `i/` and `w/` prefixes, so `annotation_old_pathname()` also strips the `c/` (commit) and `o/` (object) prefixes that `diff.mnemonicPrefix` puts on the old side, as in `git diff --cached` and `git diff HEAD`. It does so only when git printed that prefix on the `---` line: in `--- a/c/gone.txt` the `c/` is a directory.

Why not `%(file)`, `%(lineno)` and `%(lineno_old)`: in tig 2.6.1's pager view they are 0 or empty on every line. Elsewhere, on a deleted line `%(lineno)` is the new-side running counter, not 0. In the diff view (`tig show`), on per-file diffstat lines `%(lineno)` is 0 and `%(file)` is correct; on the `N files changed` summary line and on commit-message lines `%(lineno)` is the view row and `%(file)` keeps the previous selection's value. All of this was probed in a detached tmux server.

### How annotation files are named

`tig-annotate-store` keeps one note per key in `{git_dir}/tig-annotate/`:

    {encoded_key}.md     the note, edited in popup-nvim
    {encoded_key}.json   sidecar: {"side": "new" | "old", "text": the diff line as %(text) showed it}

The encoding replaces `/` with U+00B7 MIDDLE DOT (UTF-8: `C2 B7`). The sidecar is written once, when the note is first prepared, and never rewritten. Notes from before sidecars (no `.json`) export without the quoted line. Legacy `{path}:file.md` notes are listed last in `cl` as a `legacy file note`, so they can be read, edited and trashed, but `cy`, `cc` and `export` skip them with a warning, and `cc` does not trash them.

`prepare` refuses new-side lines of untracked files. Deleted lines always come from a commit or the index, so they can be annotated even when the file is gone (a deletion in `git show`, a staged deletion). A key whose note name is longer than the file system allows is refused with `Path too long to annotate`, and no temporary file is left behind.

The Outdated label compares the sidecar's line, without its diff prefix, with the working-tree line. On a combined (merge) diff the prefix is two characters (`++`, `+ `, ` +`), so when the first two characters are both diff markers, the text after either prefix may match. tig cuts `%(text)` at 1023 bytes (`SIZEOF_STR` less the terminator), so a line of that length is compared as a prefix of the working-tree line, in bytes. The store cannot tell a combined diff from an ordinary one, so on an ordinary diff a line that lost exactly one leading space, `+` or `-` in the working tree is not flagged Outdated.

Labels (the popup title, `cl` entries and export headings) name the numbering side, `new` or `old`, and say `unchanged` for a new-side note whose recorded line starts with a space: a context line keeps the new file's number, but `new` would read as an addition. A combined (merge) diff's ` +` line also starts with a space, so it is labelled `unchanged` too.

`annotations_scan()` reads the directory and caches every name ending in `.md` (stripped of `.md`) as a lookup key; sidecars and temporary files are ignored. `annotations_has_key()` encodes a key the same way and does a linear scan of the cache.

### Scan and refresh strategy

- `annotations_scan()` is called from `redraw_view_from()` (covers full redraws) and `redraw_view_dirty()` (covers cursor movement).
- A `stat()` on the annotation directory gates the actual `opendir`/`readdir` rescan — only happens when `st_mtime` or `st_ctime` changes. Scrolling costs one `stat()`, not a directory listing.

### Rendering details

- The mark is drawn after `view->ops->draw()` returns, in `draw_view_line()`.
- Position comes from `getyx()` (cursor after the draw callback).
- Status view (`LINE_STAT_STAGED/UNSTAGED/UNTRACKED`): `annotations_has_file()` prefix-matches `{encoded_path}:`, then the cursor rewinds past column field padding via a `mvwinch` backward scan.
- Overflow: if cursor is past `max_x - 2`, clamp to `max_x - 2` (overlays text).
- Color: `LINE_ANNOTATION_MARK`, configured in `bindings.tigrc` as `color annotation-mark color214 default` (orange).

## Rebuilding the patch

When tig updates (for example, 2.6.1 to 3.0), the patch will likely fail to apply. Rebuild it as follows:

```bash
# 1. Get the new tig source (the flake's, not the registry's)
new_src=$(nix build .#nixosConfigurations.$(hostname).pkgs.tig.src --print-out-paths --no-link)

# 2. Make two copies: "original" (with existing patches) and "working"
work_path=$(mktemp -d)
cp -r "$new_src" "$work_path/orig" && chmod -R u+w "$work_path/orig"
cp -r "$new_src" "$work_path/work" && chmod -R u+w "$work_path/work"

# 3. Apply the OTHER patches (not annotation-marks) to both copies
for p in pkgs/tig/patches/*.patch; do
  [[ "$p" == *annotation-marks* ]] && continue
  patch -d "$work_path/orig" -p1 < "$p"
  patch -d "$work_path/work" -p1 < "$p"
done

# 4. Port the changes to the working copy.
#    Read the old patch for intent, then edit the six files in "$work_path/work/":
#      include/tig/argv.h   — add _(argv_string, annotation, "", "") after the text entry in ARGV_ENV_INFO
#      include/tig/line.h   — add _(ANNOTATION_MARK, "") near DIFF_HEADER_FILL
#      include/tig/diff.h   — add function declarations before "extern struct view diff_view"
#      src/diff.c           — add #include <dirent.h>, #include <sys/stat.h>,
#                             and the annotation functions before diff_ops
#      src/pager.c          — fill view->env->annotation in pager_select(), after the text copy
#      src/draw.c           — add #include "tig/diff.h", #include "tig/status.h",
#                             annotation block after the diff-line-fill block in
#                             draw_view_line(), scan calls in redraw_view_from()
#                             and redraw_view_dirty()

# 5. Generate the new patch
for f in include/tig/argv.h include/tig/diff.h include/tig/line.h src/diff.c src/draw.c src/pager.c; do
  diff -ruN "$work_path/orig/$f" "$work_path/work/$f" \
    --label "i/$f" --label "w/$f" || true
done > pkgs/tig/patches/annotation-marks.patch

# 6. Build, then run the probe against the result
tig_path=$(nix build .#nixosConfigurations.$(hostname).pkgs.tig --print-out-paths --no-link | grep -v -- -man)
home/apps/tig/annotate/probe.sh "$tig_path/bin/tig"
```

## Testing checklist

### Automated

- `probe.sh <tig binary>` drives the patched tig in a private tmux server over a fixture repository. It checks `%(annotation)` on added, context, deleted, deleted-file, no-newline, header, chunk, commit-message and diffstat lines across the pager (`git show` through `GIT_PAGER`), diff (`tig show`) and stage (`tig status`) views; on staged deletions through `git diff --cached`, with `diff.mnemonicPrefix` (no `c/` in the key) and without it (a real directory named `c` keeps its name); that `%(text)` keeps tabs raw (the outdated check compares it byte for byte); and that ※ lands on a deleted line keyed `-8` and not on ` line9`, the context line at new-side 11 — the counter tig reports as `%(lineno)` on `-line8`, where the old code put the mark. Expect `0 failure(s)`.
- `test_store.py` runs in the `tig-annotate-store` build (`doCheck`), so a failing store test blocks `make switch`.

### Manual, after `make switch`

1. Open `git diff` (tig is the pager) and press Enter on a `+` line: the popup opens titled `path:N (new)`; on an unchanged line it says `(unchanged)`. Type a note, press Esc: ※ appears immediately.
2. Press Enter on a `-` line whose old and new numbers differ: the title says `(old)` and ※ lands on that line, not on a neighbour.
3. Press Enter on a diffstat or `diff --git` line: the status bar says `Not an annotatable line`.
4. Annotate a line in `.circleci/` (or any dot-directory): it shows in `cl` and in `cy`.
5. `cy`, then paste: `## path` sections, `### Line N (new|old|unchanged)` headings in numeric order, each with a `diff` quote of the line.
6. Edit a line you annotated in the working tree, then `cy`: that note carries `[Outdated — the code changed after this comment]`.
7. `cc`, then paste: the same export as `cy`; every ※ is gone, the notes and their sidecars are in `gio trash --list`, and a legacy file note is still in `cl`.
8. Reopen a note and delete all text, press Esc: ※ disappears and both the `.md` and `.json` are gone from `.git/tig-annotate/`.
9. `cl`: Enter copies the selection (notification shows the summary); `C-t` trashes a note and its sidecar; `C-e` edits. A legacy `{path}:file.md` note is listed last as a `legacy file note`.
10. Status view (`s`): files with any note show ※; split view (diff + status) shows ※ in both panes.
11. Run `cl` from a tmux session started outside the repository: it lists this repository's notes.
12. Annotate a line of a deleted file in `git show` and in `git diff --cached` (a staged deletion).
13. A file named `#(touch pwned).txt`: the popup title shows the name literally and no `pwned` file appears.

## Gotchas learned the hard way

- **Never skip drawing the mark on selected lines.** `draw_view_line()` sets `line->selected` before calling the draw callback, but `view->ops->draw()` only writes the text — it does not clear the remainder of the row. If you skip the mark on selected lines, the previous paint's mark stays in the ncurses window buffer as a ghost. Any `werase()` (Ctrl-L, view reopen, maximize) clears the ghost, and the mark is never redrawn. The fix: always draw the mark, but skip `wattrset` on selected lines so it inherits the cursor color.
- **ncurses `TRUE` vs `true`**: tig's build does not define `TRUE`; use C99 `true` (from `stdbool.h`, pulled in by tig headers).
- **Status view field padding**: `draw_filename()` pads to column width. After the draw callback, the cursor is at the field end, not the text end. Walk backward with `mvwinch` to find the last non-space character.
- **tig drops empty arguments** when it formats a binding's argv, so a positional argument after an empty variable shifts. Bindings pass `key=%(variable)` instead. List variables (`%(diffargs)`, `%(revargs)`, …) cannot sit inside a larger argument at all ("Failed to format arguments").
- **Chords need a free prefix**: `cn`, `cc`, `cy` and `cl` only fire because `vim.tigrc` has `bind generic c none`, and `bindings.tigrc` is appended after it.
- **Path encoding**: `\xc2\xb7` is U+00B7 MIDDLE DOT in UTF-8. Must match `ENCODED_SEPARATOR` in `store.py`.
- **A real U+00B7 MIDDLE DOT in a file name** is stored under the same encoded name as the path with `/` in its place, so its notes export (and list in `cl`) with `/` where the dot was. Fixing it would need a new escaping scheme in both the C patch and `store.py`, plus a migration of existing notes.
- **tmux popup options are formats**: `display-popup` expands `-T` and `-d`, so `#(...)` in a file or directory name runs a command. Double every `#` with `${var//\#/##}`: zsh reads an unescaped `#` right after `//` as a start anchor, and the escaped form works the same in bash and zsh.
- **Popup commands**: a command given as one string runs through tmux's `default-shell -c`, where a `'` in a path breaks out. Given as separate arguments, tmux runs it without a shell.
- **Popups start in the session's start directory**, not the caller's, and tig passes a relative `.git` at the top level. `cl` passes `-d` with its own working directory.
- **fzf actions**: fzf ends an action such as `reload(...)` at `)+` or `),` however the text is quoted, then runs it through `$SHELL -c`, so a value substituted into the action text can run commands. `cl` passes the git directory to its reload through the environment (`TIG_ANNOTATE_GIT_DIR`) and keeps the action text constant.
- **`diff` exit code**: `diff -ruN` returns 1 when files differ (not an error). Chain patch generation with `|| true`, not `&&`.
- **Nix flake visibility**: new patch files need `git add --intent-to-add` before `nix build` can see them.
- **`strndup`**: tig provides a compat shim (`compat/strndup.o`) via `configure.ac` — safe to use.
