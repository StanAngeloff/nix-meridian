import json
import unittest

import layout
from layout import Arrangement

COLUMN = "%9"


def window(spec, width=200, height=50, floating=()) -> str:
    """A #{window_layout} as tmux 3.8 writes it, for a tree like ("h", ["%9", ("v", ["%1", "%2"]), "%3"]):
    a pane ID is a pane, a tuple a cell split side by side ("h") or stacked ("v"),
    its panes indexed in order and sized evenly. Floating panes are given as their IDs, each small, over the top left.
    """
    index = iter(range(100))

    def build(node, w, h, x, y):
        if isinstance(node, str):
            return {
                "t": "p",
                "w": w,
                "h": h,
                "x": x,
                "y": y,
                "i": next(index),
                "I": node,
            }
        kind, children = node
        slices = layout.split(kind, len(children), w, h, x, y)
        return {"t": kind, "w": w, "h": h, "x": x, "y": y} | {
            "c": [build(child, *box) for child, box in zip(children, slices)]
        }

    root = build(spec, width, height, 0, 0)
    for pane in floating:
        entry = {"t": "p", "w": 38, "h": 8, "x": 4, "y": 2, "i": next(index), "z": 0}
        root.setdefault("c", []).append(entry | {"I": pane})
    return json.dumps({"V": 2, "L": root})


def arrangement_of(spec, **options) -> Arrangement:
    return layout.read(window(spec, **options), {COLUMN}).arrangement


class ReadTest(unittest.TestCase):
    def test_items_are_the_panes_and_groups_across_the_main_split(self):
        found = arrangement_of(("h", [COLUMN, ("v", ["%1", "%2"]), "%3"]))
        self.assertEqual(found, Arrangement("h", [["%1", "%2"], ["%3"]]))

    def test_a_column_beside_stacked_panes_leaves_them_the_main_split(self):
        found = arrangement_of(("h", [COLUMN, ("v", ["%1", ("h", ["%2", "%3"])])]))
        self.assertEqual(found, Arrangement("v", [["%1"], ["%2", "%3"]]))

    def test_a_column_squeezed_in_among_the_panes_is_still_left_out(self):
        found = arrangement_of(("v", [COLUMN, "%1", "%2"]))
        self.assertEqual(found, Arrangement("v", [["%1"], ["%2"]]))

    def test_floating_panes_are_not_items_but_are_kept(self):
        read = layout.read(window(("h", ["%1", "%2"]), floating=["%7"]), set())
        self.assertEqual(read.arrangement, Arrangement("h", [["%1"], ["%2"]]))
        self.assertEqual([leaf["I"] for leaf in read.floating], ["%7"])

    def test_a_group_split_again_inside_is_one_group(self):
        found = arrangement_of(("h", ["%1", ("v", ["%2", ("h", ["%3", "%4"])])]))
        self.assertEqual(found, Arrangement("h", [["%1"], ["%2", "%3", "%4"]]))

    def test_a_cell_split_like_its_parent_hands_it_its_children(self):
        found = arrangement_of(("h", ["%1", ("h", ["%2", "%3"])]))
        self.assertEqual(found, Arrangement("h", [["%1"], ["%2"], ["%3"]]))

    def test_one_pane_beside_the_column_is_one_item(self):
        self.assertEqual(
            arrangement_of(("h", [COLUMN, "%1"])), Arrangement("h", [["%1"]])
        )

    def test_the_old_layout_form_reads_as_nothing(self):
        self.assertIsNone(layout.read("b25d,80x24,0,0,1", set()))


# Stan's window: two reviews, each with the session that triages its findings, all side by side to begin with.
WINDOW = Arrangement("h", [["review1"], ["five"], ["review2"], ["six"]])


class JoinTest(unittest.TestCase):
    def test_stans_two_pairs(self):
        step = layout.joined(WINDOW, "five")
        self.assertEqual(step.items, [["review1", "five"], ["review2"], ["six"]])
        step = layout.joined(step, "review2")
        self.assertEqual(step.items, [["review1", "five", "review2"], ["six"]])
        step = layout.joined(step, "review2")
        self.assertEqual(step.items, [["review1", "five"], ["review2"], ["six"]])
        step = layout.joined(step, "six")
        self.assertEqual(step.items, [["review1", "five"], ["review2", "six"]])
        self.assertEqual(step.direction, "h")

    def test_in_the_middle_of_a_group_it_starts_a_group_with_the_panes_after_it(self):
        grouped = Arrangement("h", [["a", "b", "c", "d"], ["e"]])
        self.assertEqual(
            layout.joined(grouped, "c").items, [["a", "b"], ["c", "d"], ["e"]]
        )

    def test_nothing_for_the_first_pane_of_the_window_or_of_a_group(self):
        self.assertIsNone(layout.joined(WINDOW, "review1"))
        grouped = Arrangement("h", [["a"], ["b", "c"], ["d"]])
        self.assertIsNone(layout.joined(grouped, "b"))

    def test_nothing_that_would_make_the_whole_window_one_group(self):
        self.assertIsNone(layout.joined(Arrangement("h", [["a", "b"], ["c"]]), "c"))
        self.assertIsNone(layout.joined(Arrangement("v", [["a"], ["b"]]), "b"))


class LeaveTest(unittest.TestCase):
    def test_from_the_middle_the_group_splits_around_it(self):
        grouped = Arrangement("h", [["a", "b", "c", "d", "e"], ["f"]])
        self.assertEqual(
            layout.left(grouped, "c").items, [["a", "b"], ["c"], ["d", "e"], ["f"]]
        )

    def test_from_an_end_the_group_shrinks(self):
        grouped = Arrangement("h", [["a", "b", "c"], ["d"]])
        self.assertEqual(layout.left(grouped, "a").items, [["a"], ["b", "c"], ["d"]])
        self.assertEqual(layout.left(grouped, "c").items, [["a", "b"], ["c"], ["d"]])

    def test_nothing_for_a_pane_on_its_own(self):
        self.assertIsNone(layout.left(WINDOW, "five"))


def cycle(start: Arrangement, lead: str, presses: int) -> list[tuple[str, list]]:
    seen, current = [], start
    for _ in range(presses):
        current = layout.cycled(current, lead)
        seen.append((current.direction, current.items))
    return seen


class CycleTest(unittest.TestCase):
    def test_two_panes_turn_between_side_by_side_and_stacked(self):
        two = Arrangement("h", [["a"], ["b"]])
        self.assertEqual(
            cycle(two, "a", 2), [("v", [["a"], ["b"]]), ("h", [["a"], ["b"]])]
        )

    def test_three_panes_go_through_thirds_then_the_lead_halves(self):
        three = Arrangement("h", [["a"], ["b"], ["c"]])
        self.assertEqual(
            cycle(three, "b", 4),
            [
                ("v", [["a"], ["b"], ["c"]]),
                ("h", [["b"], ["a", "c"]]),
                ("v", [["b"], ["a", "c"]]),
                ("h", [["b"], ["a"], ["c"]]),
            ],
        )

    def test_four_panes_pair_up_in_order_then_turn(self):
        four = Arrangement("h", [["a"], ["b"], ["c"], ["d"]])
        self.assertEqual(
            cycle(four, "a", 2),
            [("h", [["a", "b"], ["c", "d"]]), ("v", [["a", "b"], ["c", "d"]])],
        )

    def test_four_panes_keep_their_pairs(self):
        pairs = Arrangement("h", [["review1", "five"], ["review2", "six"]])
        self.assertEqual(
            cycle(pairs, "six", 1), [("v", [["review1", "five"], ["review2", "six"]])]
        )

    def test_five_panes_make_a_grid_of_columns_then_turn(self):
        five = Arrangement("v", [["a"], ["b"], ["c"], ["d"], ["e"]])
        self.assertEqual(
            cycle(five, "a", 2),
            [
                ("h", [["a", "b"], ["c", "d"], ["e"]]),
                ("v", [["a", "b"], ["c", "d"], ["e"]]),
            ],
        )

    def test_one_pane_has_nothing_to_cycle(self):
        self.assertIsNone(layout.cycled(Arrangement("h", [["a"]]), "a"))


class DocumentTest(unittest.TestCase):
    def setUp(self):
        spec = ("h", [COLUMN, "%1", "%2", "%3", "%4"])
        self.read = layout.read(window(spec, floating=["%7"]), {COLUMN})
        self.pairs = Arrangement("h", [["%1", "%2"], ["%3", "%4"]])

    def built(self, arrangement, column_width=36):
        return json.loads(layout.document(self.read, arrangement, column_width))["L"]

    def test_pairs_beside_the_column_fill_the_window_evenly(self):
        root = self.built(self.pairs)
        column, left_pair, right_pair, floating = root["c"]
        self.assertEqual((root["t"], column["I"], column["w"]), ("h", COLUMN, 36))
        self.assertEqual(
            (left_pair["t"], left_pair["x"], left_pair["w"]), ("v", 37, 81)
        )
        self.assertEqual((right_pair["x"], right_pair["w"]), (119, 81))
        self.assertEqual([p["h"] for p in left_pair["c"]], [25, 24])
        self.assertEqual(floating["I"], "%7")
        self.assertEqual((floating["w"], floating["h"]), (38, 8))

    def test_panes_keep_their_index_so_tmux_puts_each_where_it_goes(self):
        moved = Arrangement("h", [["%4", "%1"], ["%2", "%3"]])
        left_pair = self.built(moved)["c"][1]
        self.assertEqual(
            [(p["I"], p["i"]) for p in left_pair["c"]], [("%4", 4), ("%1", 1)]
        )

    def test_stacked_items_sit_in_one_cell_beside_the_column(self):
        root = self.built(Arrangement("v", [["%1", "%2"], ["%3", "%4"]]))
        content = root["c"][1]
        self.assertEqual((content["t"], content["x"], content["w"]), ("v", 37, 163))
        self.assertEqual([row["t"] for row in content["c"]], ["h", "h"])

    def test_without_a_column_the_items_fill_the_window(self):
        read = layout.read(window(("v", ["%1", "%2"])), set())
        root = json.loads(layout.document(read, Arrangement("h", [["%1"], ["%2"]]), 36))
        self.assertEqual(
            [(p["x"], p["w"]) for p in root["L"]["c"]], [(0, 100), (101, 99)]
        )


class ArrangedTest(unittest.TestCase):
    def test_an_even_layout_cycles_and_an_uneven_one_is_evened_out_first(self):
        start = layout.read(window(("h", [COLUMN, "%1", "%2"])), {COLUMN})
        even = layout.document(start, start.arrangement, 36)
        self.assertEqual(
            layout.arranged(layout.read(even, {COLUMN}), "%1", 36),
            Arrangement("v", [["%1"], ["%2"]]),
        )
        uneven = json.loads(even)
        _, first, second = uneven["L"]["c"]
        first["w"], second["x"], second["w"] = 120, 158, 42
        self.assertEqual(
            layout.arranged(layout.read(json.dumps(uneven), {COLUMN}), "%1", 36),
            Arrangement("h", [["%1"], ["%2"]]),
        )

    def test_a_squeezed_column_counts_as_uneven(self):
        read = layout.read(window(("v", [COLUMN, "%1", "%2"])), {COLUMN})
        self.assertEqual(
            layout.arranged(read, "%1", 36), Arrangement("v", [["%1"], ["%2"]])
        )

    def test_four_panes_side_by_side_go_straight_to_pairs(self):
        read = layout.read(window(("h", ["%1", "%2", "%3", "%4"])), set())
        self.assertEqual(
            layout.arranged(read, "%1", 36).items, [["%1", "%2"], ["%3", "%4"]]
        )


if __name__ == "__main__":
    unittest.main()
