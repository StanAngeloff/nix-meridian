import colorsys
import re
import unittest

import draw
import model
import test_links
from model import Branch, Pane, Session, Window

SESSIONS = [
    Session(
        "default",
        [
            Window("@1", 1, "task", [Pane("%1", "claude", "~", "◐ Do it", "working")]),
            Window(
                "@2",
                2,
                "other",
                [
                    Pane("%2", "claude", "~", "✳ Wait", "blocked"),
                    Pane("%3", "tig", "~/repo"),
                ],
            ),
        ],
    ),
    Session("scratch", [Window("@5", 1, "notes", [Pane("%5", "nvim", "~/notes")])]),
]


def footer(canvas) -> str:
    """The text of the last rows, where the key hints go."""
    return " ".join(canvas.text(y) for y in range(canvas.rows - 3, canvas.rows))


def render(
    cursor="@1",
    focused=False,
    rows=14,
    cols=30,
    sessions=None,
    dragging="",
    help=False,
    rules=(),
    hints=None,
    glyphs=draw.NERD_FONT,
    expanded=frozenset(),
):
    view = draw.View(
        open_window="@1",
        cursor=cursor,
        focused=focused,
        dragging=dragging,
        help=help,
        glyphs=glyphs,
        expanded=expanded,
    )
    return draw.draw(sessions or SESSIONS, view, cols, rows, rules, hints)


class TreeTest(unittest.TestCase):
    def test_windows_branch_into_their_panes_and_the_trunk_ends_each_session(self):
        canvas = render()
        lines = [canvas.text(y).rstrip() for y in range(10)]
        self.assertEqual(lines[1], "  1│ task")
        self.assertTrue(lines[2].startswith("   │ └─ ● Do it"))
        self.assertTrue(lines[4].startswith("   │ ├─ ● Wait"))
        self.assertTrue(lines[5].startswith("   ╵ └─"))
        self.assertIn("tig  ~/repo", lines[5])
        self.assertEqual(lines[6], "")
        self.assertTrue(lines[7].startswith(" scratch "))
        self.assertTrue(lines[9].startswith("   ╵ └─"))

    def test_the_open_window_is_cyan_with_dots_in_the_darker_shade(self):
        canvas = render()
        self.assertEqual(canvas.cells[1][0][2], draw.FOCUSED_TAB_BG)
        self.assertEqual(
            canvas.cells[2][draw.CONTENT_X + 3][1], draw.DOT_ON_CYAN["working"]
        )
        self.assertEqual(
            canvas.cells[4][draw.CONTENT_X + 3][1], draw.DOT_ON_DARK["blocked"]
        )

    def test_in_the_open_window_the_pane_you_are_in_is_darker(self):
        panes = [
            Pane("%2", "claude", "~", "✳ Wait", "blocked"),
            Pane("%3", "tig", "~/repo", active=True),
        ]
        sessions = [
            Session(
                "default",
                [
                    Window("@1", 1, "task", panes),
                    Window("@2", 2, "other", [Pane("%4", "tig", "~", active=True)]),
                ],
            )
        ]
        canvas = render(sessions=sessions)
        label_x = draw.CONTENT_X + 5
        self.assertTrue(canvas.text(3).startswith("   │ └─ \ue702 tig"))
        colours = [canvas.cells[y][label_x][1] for y in (2, 3, 5)]
        self.assertEqual(
            colours, [draw.FOCUSED_TAB_DIM, draw.FOCUSED_TAB_HERE, draw.DIM]
        )
        self.assertFalse(any(cell[3] for cell in canvas.cells[3][label_x:]))

    def test_long_text_ends_in_an_ellipsis_inside_the_pane(self):
        canvas = render(cols=13)
        self.assertEqual(canvas.text(2).rstrip()[-1], draw.ELLIPSIS)
        self.assertEqual(len(canvas.text(2)), 13)


class IconTest(unittest.TestCase):
    def test_the_issue_board_gets_a_ticket_whatever_shell_runs_it(self):
        board = Pane("%9", "zsh", "~", role="issues")
        self.assertEqual(draw.icon(board, on_cyan=False)[0], draw.ROLE_ICONS["issues"])
        self.assertEqual(draw.icon(Pane("%8", "zsh", "~"), False)[0], draw.SHELL_ICON)

    def test_a_nested_tmux_gets_the_tmux_icon_and_label(self):
        nested = Pane("%7", "bash", "~/work", role="tmux")
        self.assertEqual(draw.icon(nested, on_cyan=False)[0], draw.ROLE_ICONS["tmux"])
        self.assertEqual(nested.label, "tmux  ~/work")


class PlainGlyphTest(unittest.TestCase):
    def test_the_phone_glyphs_need_no_nerd_font(self):
        panes = [Pane("%7", "nvim", "~"), Pane("%8", "zsh", "~", role="issues")]
        window = Window("@7", 7, "webapp@ticket-101[lint]", panes)
        canvas = render(
            sessions=[Session("default", [window])], cols=36, glyphs=draw.PLAIN
        )
        text = "".join(canvas.text(y) for y in range(canvas.rows))
        self.assertFalse(any("\ue000" <= character <= "\uf8ff" for character in text))
        self.assertTrue(canvas.text(0).startswith(" default  ─"))
        self.assertTrue(canvas.text(1).rstrip().endswith("@ webapp"))
        self.assertEqual(canvas.text(2)[draw.CONTENT_X + 3], "○")
        self.assertEqual(canvas.text(3)[draw.CONTENT_X + 3], "○")


def workflow(agents):
    children = [Branch("agent", f"w{i}", f"review:{i}", True) for i in range(agents)]
    return Branch(
        "workflow",
        "wf_1",
        "review-changes",
        True,
        detail="Review 2/3",
        children=children,
    )


class BranchTest(unittest.TestCase):
    def frame(self, branches, expanded=frozenset(), rows=30, cols=36):
        task = Pane("%1", "claude", "~", "✳ Do it", "working", branches=branches)
        sessions = [Session("default", [Window("@1", 1, "task", [task])])]
        return render(sessions=sessions, rows=rows, cols=cols, expanded=expanded)

    def test_branches_hang_under_their_pane_and_the_trunk_ends_on_the_last(self):
        research = Branch(
            "agent",
            "a1",
            "research",
            True,
            children=[Branch("agent", "a2", "chromium", True)],
        )
        shell = Branch("shell", "b1", "$ sleep 600", False, ended_at=1.0)
        canvas = self.frame([research, shell])
        lines = [canvas.text(y).rstrip() for y in range(1, 6)]
        self.assertEqual(
            lines,
            [
                "  1│ task",
                "   │ └─ ● Do it",
                "   │    ├─ ● research",
                "   │    │  └─ ● chromium",
                f"   ╵    └─ {draw.TICK} $ sleep 600",
            ],
        )
        self.assertEqual(
            canvas.cells[3][draw.CONTENT_X + 6][1], draw.DOT_ON_CYAN["working"]
        )
        self.assertEqual(
            canvas.cells[5][draw.CONTENT_X + 6][1], draw.DOT_ON_CYAN["read"]
        )

    def test_a_stopped_branch_shows_a_cross_in_the_blocked_shade(self):
        stopped = Branch("agent", "a1", "wait", False, ended_at=1.0, stopped=True)
        canvas = self.frame([stopped])
        self.assertEqual(canvas.text(3).rstrip(), f"   ╵    └─ {draw.CROSS} wait")
        self.assertEqual(
            canvas.cells[3][draw.CONTENT_X + 6][1], draw.DOT_ON_CYAN["blocked"]
        )

    def test_a_branch_under_a_pane_with_panes_after_it_keeps_that_panes_line(self):
        agent = Branch("agent", "a1", "research", True)
        first = Pane("%1", "claude", "~", "✳ Do it", "working", branches=[agent])
        second = Pane("%2", "tig", "~/repo")
        sessions = [Session("default", [Window("@1", 1, "task", [first, second])])]
        canvas = render(sessions=sessions, rows=10, cols=36)
        lines = [canvas.text(y).rstrip() for y in range(1, 5)]
        self.assertEqual(lines[1], "   │ ├─ ● Do it")
        self.assertEqual(lines[2], "   │ │  └─ ● research")
        self.assertTrue(lines[3].startswith("   ╵ └─"))

    def test_a_branch_row_opens_its_pane(self):
        canvas = self.frame([Branch("agent", "a1", "research", True)])
        self.assertEqual(canvas.targets[3], ("@1", "%1"))

    def test_a_workflow_is_one_line_with_its_progress_at_the_right_until_expanded(self):
        canvas = self.frame([workflow(3)], cols=40)
        line = canvas.text(3).rstrip()
        self.assertTrue(line.startswith("   ╵    └─ ● review-changes"))
        self.assertTrue(line.endswith("Review 2/3"))
        narrow = self.frame([workflow(3)]).text(3).rstrip()
        self.assertTrue(narrow.startswith("   ╵    └─ ● review-changes"))
        self.assertTrue(narrow.endswith(" 2/3") and "Review" not in narrow)
        self.assertEqual(canvas.text(4).strip(), "")
        expanded = self.frame([workflow(3)], expanded=frozenset({"@1"}))
        self.assertEqual(expanded.text(4).rstrip(), "   │       ├─ ● review:0")
        self.assertEqual(expanded.text(6).rstrip(), "   ╵       └─ ● review:2")

    def test_an_expanded_workflow_shows_at_most_twenty_rows_the_last_counting_the_rest(
        self,
    ):
        canvas = self.frame([workflow(25)], expanded=frozenset({"@1"}), rows=40)
        rows = [canvas.text(y).rstrip() for y in range(4, 4 + draw.WORKFLOW_ROWS)]
        self.assertEqual(rows[-1], f"   ╵       └─   {draw.ELLIPSIS} 6 more")
        self.assertEqual(canvas.text(4 + draw.WORKFLOW_ROWS).strip(), "")


def grouped_window(last_zsh=True):
    panes = [
        Pane("%1", "claude", "~", "✳ review 1", "read", group=1),
        Pane("%5", "claude", "~", "✳ #5", "read", group=1),
        Pane("%2", "claude", "~", "✳ review 2", "read", group=2),
        Pane("%6", "claude", "~", "✳ #6", "read", group=2),
    ]
    if last_zsh:
        panes.append(Pane("%7", "zsh", "~"))
    return [Session("default", [Window("@1", 1, "pairs", panes)])]


class GroupTest(unittest.TestCase):
    def test_a_groups_panes_hang_off_a_fork_on_its_first(self):
        canvas = render(sessions=grouped_window(), cols=36)
        lines = [canvas.text(y).rstrip() for y in range(1, 7)]
        self.assertEqual(
            lines,
            [
                "  1│ pairs",
                "   │ ├─┬ ● review 1",
                "   │ │ └ ● #5",
                "   │ ├─┬ ● review 2",
                "   │ │ └ ● #6",
                "   ╵ └─ \uf489 zsh  ~",
            ],
        )

    def test_a_group_last_in_its_window_ends_the_windows_line(self):
        canvas = render(sessions=grouped_window(last_zsh=False), cols=36)
        self.assertEqual(canvas.text(4).rstrip(), "   │ └─┬ ● review 2")
        self.assertEqual(canvas.text(5).rstrip(), "   ╵   └ ● #6")

    def test_a_branch_under_a_grouped_pane_keeps_both_lines(self):
        sessions = grouped_window()
        sessions[0].windows[0].panes[0].branches = [
            Branch("agent", "a1", "research", True)
        ]
        canvas = render(sessions=sessions, cols=36)
        self.assertEqual(canvas.text(3).rstrip(), "   │ │ │ └─ ● research")
        self.assertEqual(canvas.targets[3], ("@1", "%1"))

    def test_while_grouping_the_window_is_grey_and_the_pane_under_the_cursor_cyan(self):
        grey = ("▌", draw.FOCUSED_TAB_BG, draw.CURSOR_BG)
        cyan = ("▌", draw.CURSOR_ON_CYAN, draw.FOCUSED_TAB_BG)
        for open_window in ("@1", "@9"):  # the window the navigator is in, or another
            view = draw.View(open_window, "@1", True, cursor_pane="%5")
            canvas = draw.draw(grouped_window(), view, 36, 14)
            self.assertEqual(canvas.cells[1][0][:3], grey)
            self.assertEqual(canvas.cells[2][0][:3], grey)
            self.assertEqual(canvas.cells[3][0][:3], cyan)
            self.assertEqual(canvas.cells[4][0][:3], grey)
            self.assertEqual(
                canvas.cells[3][draw.CONTENT_X + 4][1], draw.DOT_ON_CYAN["read"]
            )


def sectioned(*more):
    """The first session with an empty section header named Work between its two windows, then the windows given."""
    work = Window("@3", 3, "-- Work --", [Pane("%6", "zsh", "~")], "Work", True)
    windows = SESSIONS[0].windows
    return [Session("default", [windows[0], work, windows[1], *more])]


PROJECTS = Window(
    "@7", 7, "--- Projects ---", [Pane("%7", "nvim", "/data/x")], section="Projects"
)


class SectionTest(unittest.TestCase):
    def test_an_empty_section_header_is_a_band_with_its_title_the_trunk_through_it(
        self,
    ):
        canvas = render(sessions=sectioned(), cols=30)
        lines = [canvas.text(y).rstrip() for y in range(7)]
        self.assertEqual(lines[4], "   │ Work")
        self.assertEqual(lines[5], "  2│ other")
        band, colours = canvas.cells[4], draw.GREY_SECTION
        self.assertEqual({cell[2] for cell in band}, {colours.band})
        self.assertFalse(any(cell[5] for cell in band), "no line on the band itself")
        self.assertEqual(band[draw.TRUNK_X][1], draw.SECTION_TRUNK)
        self.assertEqual(
            band[draw.CONTENT_X][:4], ("W", colours.title, colours.band, True)
        )
        self.assertEqual(canvas.targets[4], ("@3", ""))

    def test_a_divider_above_the_band_underlined_across_the_trunk_crossing_it(self):
        canvas = render(sessions=sectioned(), cols=30)
        self.assertEqual(canvas.text(3).rstrip(), "   │")
        divider = canvas.cells[3]
        self.assertTrue(all(cell[5] for cell in divider), "underlined across")
        self.assertEqual({cell[1] for cell in divider}, {draw.GREY_SECTION.line})
        self.assertEqual({cell[2] for cell in divider}, {draw.TERMINAL_BG})
        self.assertEqual(canvas.targets[3], ("@3", ""))

    def test_a_section_header_first_in_its_session_has_no_divider(self):
        first = Session("default", sectioned()[0].windows[1:])
        canvas = render(sessions=[first], cols=30)
        self.assertEqual(canvas.text(1).rstrip(), "   │ Work")
        self.assertFalse(any(cell[5] for row in canvas.cells for cell in row))

    def test_a_section_header_with_work_in_it_shows_its_panes_below_its_band(self):
        canvas = render(sessions=sectioned(PROJECTS), rows=16)
        lines = [canvas.text(y).rstrip() for y in range(12)]
        self.assertEqual(lines[8], "   │")
        self.assertEqual(lines[9], "   │ Projects")
        self.assertTrue(lines[10].startswith("   ╵ └─"))
        self.assertIn("nvim  /data/x", lines[10])
        self.assertEqual(canvas.cells[10][0][2], draw.TERMINAL_BG, "only the band")
        self.assertEqual(canvas.targets[10], ("@7", "%7"))

    def test_under_the_cursor_it_gets_the_bar_and_open_it_turns_cyan(self):
        canvas = render(sessions=sectioned(), cursor="@3", focused=True)
        lighter = draw.GREY_SECTION.band_under_cursor
        self.assertEqual(canvas.cells[4][0][:3], ("▌", draw.FOCUSED_TAB_BG, lighter))
        self.assertEqual(canvas.cells[3][0][2], draw.TERMINAL_BG, "the divider stays")
        view = draw.View(open_window="@3", cursor="@3", focused=False)
        canvas = draw.draw(sectioned(), view, 30, 14)
        self.assertEqual(canvas.cells[4][0][2], draw.FOCUSED_TAB_BG)
        self.assertEqual(canvas.cells[4][draw.TRUNK_X][1], draw.FOCUSED_TAB_DIM)
        self.assertEqual(canvas.cells[4][draw.CONTENT_X][1], draw.FOCUSED_TAB_FG)
        self.assertEqual(canvas.cells[3][0][2], draw.TERMINAL_BG, "the divider stays")

    def test_a_section_header_last_in_its_session_ends_the_trunk(self):
        last = Window("@9", 9, "- Last -", [Pane("%9", "zsh", "~")], "Last", True)
        canvas = render(sessions=sectioned(last), rows=16)
        self.assertEqual(canvas.text(9).rstrip(), "   ╵ Last")
        self.assertEqual(canvas.text(8).rstrip(), "   │")

    def test_the_divider_goes_out_underlined_in_its_colour(self):
        ansi = render(sessions=sectioned()).to_ansi()
        line = draw.GREY_SECTION.line
        underline = f"\x1b[4m{draw.sgr(line, 58)}{draw.sgr(line, 38)}\x1b[49m   "
        self.assertIn(underline, ansi)

    def test_space_steps_from_grey_through_the_rainbow_and_back(self):
        seen, colour = [], ""
        for _ in range(7):
            colour = draw.next_section_colour(colour)
            seen.append(colour)
        self.assertEqual(
            seen, ["red", "amber", "yellow", "green", "blue", "purple", ""]
        )
        self.assertEqual(draw.section_colours(""), draw.GREY_SECTION)
        self.assertEqual(draw.section_colours("teal"), draw.GREY_SECTION)

    def test_a_coloured_section_draws_its_band_title_and_divider_in_its_shades(self):
        sessions = sectioned()
        sessions[0].windows[1].section_colour = "blue"
        canvas = render(sessions=sessions, cols=30)
        blue = draw.hue_colours(draw.SECTION_HUES["blue"])
        self.assertEqual(canvas.cells[4][draw.CONTENT_X][1:3], (blue.title, blue.band))
        divider = canvas.cells[3]
        self.assertEqual({cell[5] for cell in divider}, {blue.line}, "the line")
        self.assertEqual(divider[draw.TRUNK_X][:2], ("│", draw.DIMMER), "grey trunk")

    def test_a_hue_gives_shades_from_a_dark_band_up_to_a_bright_title(self):
        colours = draw.hue_colours(240)
        shades = [
            colours.band,
            colours.band_under_cursor,
            colours.line,
            colours.title,
        ]
        hls = [
            colorsys.rgb_to_hls(*(int(c[i : i + 2], 16) / 255 for i in (1, 3, 5)))
            for c in shades
        ]
        self.assertEqual([round(h * 360) for h, _, _ in hls], [240] * 4)
        self.assertEqual(
            [lightness for _, lightness, _ in hls],
            sorted(lightness for _, lightness, _ in hls),
        )


class DragTest(unittest.TestCase):
    def test_a_dragged_window_shows_raised_in_its_new_place_with_the_numbers_after_the_drop(
        self,
    ):
        sessions = model.reordered(SESSIONS, "@1", 1, 1)
        canvas = render(sessions=sessions, dragging="@1", focused=True)
        lines = [canvas.text(y).rstrip() for y in range(6)]
        self.assertEqual(lines[1], "  1│ other")
        self.assertEqual(lines[4], "▌ 2│ task")
        self.assertEqual(canvas.cells[4][2][2], draw.LIFTED_BG)


class NameTest(unittest.TestCase):
    def frame(self, name, cols):
        sessions = [
            Session("default", [Window("@7", 7, name, [Pane("%7", "zsh", "~")])])
        ]
        return render(sessions=sessions, cols=cols)

    def test_the_title_then_the_repository_dimmed_against_the_right_edge(self):
        canvas = self.frame("webapp@ticket-101[lint triage]", 36)
        line = canvas.text(1)
        self.assertTrue(line.startswith("  7│ lint triage "))
        self.assertTrue(line.rstrip().endswith(draw.REPOSITORY_ICON + " webapp"))
        self.assertEqual(canvas.cells[1][34][1], draw.DIM)

    def test_the_repository_gives_way_first_then_goes(self):
        long_title = "webapp@ticket-101[continuous integration monitoring]"
        line = self.frame(long_title, 36).text(1).rstrip()
        self.assertIn("continuous", line)
        self.assertTrue(line.endswith(draw.ELLIPSIS) or "webapp" in line)
        narrow = self.frame(long_title, 20).text(1).rstrip()
        self.assertNotIn(draw.REPOSITORY_ICON, narrow)


class LinkTest(unittest.TestCase):
    def frame(self, title, cols=36):
        task = Pane("%7", "claude", "~", "✳ sc-123/finish", "read")
        sessions = [Session("default", [Window("@7", 7, title, [task])])]
        return render(sessions=sessions, cols=cols, rules=test_links.RULES)

    def test_an_issue_in_a_pane_task_opens_its_story(self):
        canvas = self.frame("task")
        x = draw.CONTENT_X + 5
        self.assertEqual(canvas.text(2)[x : x + 7], "sc-123/")
        urls = [cell[4] for cell in canvas.cells[2][x : x + 7]]
        self.assertEqual(urls, [test_links.STORY + "123"] * 6 + [""])
        # SGR changes may fall anywhere; what matters is where the link starts and ends around the text.
        ansi = re.sub(r"\x1b\[[0-9;]*m", "", canvas.to_ansi())
        link = f"\x1b]8;;{test_links.STORY}123\x1b\\sc-123\x1b]8;;\x1b\\/finish"
        self.assertIn(link, ansi)

    def test_a_cut_title_still_opens_the_story_it_named_but_its_ellipsis_does_not(
        self,
    ):
        canvas = self.frame("sc-12345 continuous integration", cols=12)
        title = canvas.cells[1][draw.CONTENT_X : draw.CONTENT_X + 6]
        self.assertEqual("".join(cell[0] for cell in title), "sc-12" + draw.ELLIPSIS)
        urls = [cell[4] for cell in title]
        self.assertEqual(urls, [test_links.STORY + "12345"] * 5 + [""])

    def test_without_rules_nothing_links(self):
        canvas = render()
        self.assertNotIn("\x1b]8", canvas.to_ansi())


class TargetTest(unittest.TestCase):
    def test_rows_map_to_their_window_and_pane_and_headers_to_nothing(self):
        targets = render().targets
        self.assertNotIn(0, targets)
        self.assertEqual(targets[1], ("@1", ""))
        self.assertEqual(targets[2], ("@1", "%1"))
        self.assertEqual(targets[5], ("@2", "%3"))
        self.assertNotIn(6, targets)
        self.assertEqual(targets[9], ("@5", "%5"))

    def test_a_scroll_marker_row_opens_nothing(self):
        targets = render(cursor="@5", focused=True, rows=6).targets
        self.assertNotIn(0, targets)


class FocusTest(unittest.TestCase):
    def test_unfocused_shows_no_cursor_and_no_hints(self):
        canvas = render(cursor="@2")
        self.assertNotIn("move", footer(canvas))
        self.assertEqual(canvas.cells[3][0][0], " ")

    def test_focused_marks_the_cursor_window_but_shows_no_hints_until_asked(self):
        canvas = render(cursor="@2", focused=True)
        self.assertNotIn("move", footer(canvas))
        self.assertEqual(
            canvas.cells[3][0][:3], ("▌", draw.FOCUSED_TAB_BG, draw.CURSOR_BG)
        )

    def test_hints_show_when_asked_for_and_fit_the_column(self):
        canvas = render(cursor="@2", focused=True, help=True, cols=36)
        self.assertIn("move", footer(canvas))
        self.assertIn("? hide", footer(canvas))
        self.assertIn("reorder", footer(canvas))
        self.assertTrue(all(len(canvas.text(y).rstrip()) <= 36 for y in range(14)))
        unfocused = render(cursor="@2", focused=False, help=True)
        self.assertNotIn("move", footer(unfocused))

    def test_hints_given_by_the_caller_show_whatever_the_focus(self):
        canvas = render(cursor="@2", focused=False, hints=[[("n", "new")]])
        self.assertIn("n new", footer(canvas))
        self.assertNotIn("reorder", footer(canvas))

    def test_the_cursor_on_the_open_window_has_a_white_bar(self):
        canvas = render(cursor="@1", focused=True)
        self.assertEqual(canvas.cells[1][0][:2], ("▌", draw.CURSOR_ON_CYAN))


class ScrollTest(unittest.TestCase):
    def test_the_cursor_window_stays_in_view(self):
        canvas = render(cursor="@5", focused=True, rows=6)
        shown = [canvas.text(y) for y in range(4)]
        self.assertTrue(any("notes" in line for line in shown))
        self.assertTrue(any("more" in line for line in shown))


if __name__ == "__main__":
    unittest.main()
