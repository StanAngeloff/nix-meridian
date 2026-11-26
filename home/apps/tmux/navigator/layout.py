"""A window's panes as tmux lays them out, and the layouts the navigator gives a window: groups and prefix Space.

tmux 3.8 writes #{window_layout} as JSON: a tree of cells split side by side ("h") or stacked ("v"),
down to panes ("p") with their ID ("I") and index ("i"), floating panes among them ("z").
select-layout takes the same JSON back and places each pane by its index,
so one command can regroup a window's panes, move them and size them.

The navigator reads the tree as a row of items across the window's main split.
An item is a pane on its own, or a group: the panes tmux draws together in one cell across that split,
such as a column of stacked panes in a window split side by side.
The navigator's column and floating panes are not items, and every layout applied keeps them.
"""

import json
import math
from dataclasses import dataclass

# How far, in cells, a pane may be from the size an even layout gives it and still count as even:
# tmux's own presets hand the spare cells to other panes than an even layout here does.
EVEN_SLACK = 2
OTHER = {"h": "v", "v": "h"}


@dataclass
class Arrangement:
    """The items of a window across its main split, each a list of pane IDs; an item of two or more is a group.

    direction "h" puts the items side by side and stacks each group's panes;
    "v" stacks the items and puts each group's panes side by side.
    """

    direction: str
    items: list[list[str]]

    @property
    def panes(self) -> list[str]:
        return [pane for item in self.items for pane in item]


@dataclass
class Layout:
    """A window's layout as read: its size, its arrangement, and what every layout applied has to carry over."""

    width: int
    height: int
    arrangement: Arrangement
    leaves: dict[str, dict]  # each item pane's own entry in the tree, by pane ID
    # The navigator's column or a placeholder, when the window has one.
    column: dict | None
    floating: list[dict]


def read(text: str, columns: set[str]) -> Layout | None:
    """The layout in a #{window_layout}, with the panes in columns taken as the window's column;
    None when tmux wrote something other than the JSON form."""
    try:
        root = json.loads(text)["L"]
    except (ValueError, KeyError, TypeError):
        return None
    leaves, column, floating = {}, None, []
    for leaf in all_leaves(root):
        if "z" in leaf:
            floating.append(leaf)
        elif leaf.get("I") in columns:
            column = column or leaf
        else:
            leaves[leaf["I"]] = leaf
    tree = tidied(root, set(leaves))
    if tree is None:
        arrangement = Arrangement("h", [])
    elif tree["t"] == "p":
        arrangement = Arrangement("h", [[tree["I"]]])
    else:
        items = [[leaf["I"] for leaf in all_leaves(child)] for child in tree["c"]]
        arrangement = Arrangement(tree["t"], items)
    return Layout(root["w"], root["h"], arrangement, leaves, column, floating)


def all_leaves(node: dict) -> list[dict]:
    if node["t"] == "p":
        return [node]
    return [leaf for child in node["c"] for leaf in all_leaves(child)]


def tidied(node: dict, kept: set[str]) -> dict | None:
    """The tree of the kept panes alone: a cell left with one child becomes that child,
    and a cell split the same way as its parent gives the parent its children,
    so every cell splits the other way from the one around it.
    """
    if node["t"] == "p":
        return node if node.get("I") in kept else None
    children = []
    for child in node["c"]:
        child = tidied(child, kept)
        if child is None:
            continue
        if child["t"] == node["t"]:
            children += child["c"]
        else:
            children.append(child)
    if not children:
        return None
    if len(children) == 1:
        return children[0]
    return {"t": node["t"], "c": children}


def place(arrangement: Arrangement, pane: str) -> tuple[int, int]:
    """The pane's item and its place in that item."""
    for i, item in enumerate(arrangement.items):
        if pane in item:
            return i, item.index(pane)
    raise ValueError(pane)


def joined(arrangement: Arrangement, pane: str) -> Arrangement | None:
    """l on a pane: on its own, it joins the item above it, a pane on its own or a group, into one group;
    in a group, it and the panes after it start a group of their own (on its own when it was the last).
    Nothing for the first pane of the window or of a group, nor for a join that would leave the whole window one group.
    """
    i, j = place(arrangement, pane)
    items = [list(item) for item in arrangement.items]
    if len(items[i]) > 1:
        if j == 0:
            return None
        items[i : i + 1] = [items[i][:j], items[i][j:]]
    else:
        if i == 0 or len(items) == 2:
            return None
        items[i - 1 : i + 1] = [items[i - 1] + items[i]]
    return Arrangement(arrangement.direction, items)


def left(arrangement: Arrangement, pane: str) -> Arrangement | None:
    """h on a pane in a group: it leaves the group and stays in its place,
    splitting the group in two when it was in the middle. Nothing for a pane on its own.
    """
    i, j = place(arrangement, pane)
    item = arrangement.items[i]
    if len(item) == 1:
        return None
    pieces = [piece for piece in (item[:j], [pane], item[j + 1 :]) if piece]
    items = arrangement.items[:i] + pieces + arrangement.items[i + 1 :]
    return Arrangement(arrangement.direction, [list(item) for item in items])


def cycled(arrangement: Arrangement, lead: str) -> Arrangement | None:
    """prefix Space on a window already laid out evenly: the next arrangement for its number of panes.

    2 panes: side by side, stacked.
    3: side by side, stacked, lead's own half on the left with the other two stacked beside it,
    then lead's half on top with the other two side by side below;
    lead is the pane prefix Space was pressed in, and a lead already there stays.
    4: two by two, pairs as columns, then pairs as rows; the pairs already there stay, else the panes pair in order.
    5 or more: a grid, as columns, the first time; with groups, they turn between columns and rows.
    """
    panes = arrangement.panes
    count = len(panes)
    direction = arrangement.direction
    singles = [[pane] for pane in panes]
    shape = sorted(len(item) for item in arrangement.items)
    if count < 2:
        return None
    if count == 2:
        return Arrangement(OTHER[direction], singles)
    if count == 3:
        if shape == [1, 1, 1] and direction == "h":
            return Arrangement("v", singles)
        if shape == [1, 1, 1]:
            lead = lead if lead in panes else panes[0]
            return Arrangement("h", [[lead], [pane for pane in panes if pane != lead]])
        if direction == "h":
            return Arrangement("v", arrangement.items)
        return Arrangement("h", singles)
    if count == 4:
        if shape == [2, 2]:
            return Arrangement(OTHER[direction], arrangement.items)
        return Arrangement("h", [panes[0:2], panes[2:4]])
    if max(shape) > 1:
        return Arrangement(OTHER[direction], arrangement.items)
    per_column = math.ceil(count / math.ceil(math.sqrt(count)))
    return Arrangement(
        "h", [panes[k : k + per_column] for k in range(0, count, per_column)]
    )


def in_cycle(arrangement: Arrangement) -> bool:
    """Whether the arrangement is one cycled gives its number of panes:
    four panes only as two pairs, five or more only with groups; two and three panes have no other.
    """
    count = len(arrangement.panes)
    shape = sorted(len(item) for item in arrangement.items)
    if count == 4:
        return shape == [2, 2]
    if count >= 5:
        return max(shape) > 1
    return True


def arranged(layout: Layout, lead: str, column_width: int) -> Arrangement | None:
    """What prefix Space gives the window: its own arrangement evened out, when it is one of the cycle's and uneven,
    else the next one in the cycle."""
    current = layout.arrangement
    if len(current.panes) < 2:
        return None
    if in_cycle(current) and not is_even(layout, current, column_width):
        return current
    return cycled(current, lead)


def is_even(layout: Layout, arrangement: Arrangement, column_width: int) -> bool:
    """Whether every pane, and the column, already has about the size an even layout of the arrangement gives it."""
    built = all_leaves(tree(layout, arrangement, column_width))
    actual = {leaf.get("I"): leaf for leaf in leaves_as_read(layout)}
    for leaf in built:
        if "z" in leaf:
            continue
        found = actual.get(leaf.get("I"))
        if found is None:
            return False
        for key in ("w", "h", "x", "y"):
            if abs(found[key] - leaf[key]) > EVEN_SLACK:
                return False
    return True


def leaves_as_read(layout: Layout) -> list[dict]:
    column = [layout.column] if layout.column else []
    return column + list(layout.leaves.values())


def document(layout: Layout, arrangement: Arrangement, column_width: int) -> str:
    """The JSON select-layout takes for the arrangement, every item and every group's panes sharing their space evenly;
    the column is column_width wide down the left edge, and floating panes stay as they are.
    """
    root = tree(layout, arrangement, column_width)
    return json.dumps({"V": 2, "L": root}, separators=(",", ":"))


def tree(layout: Layout, arrangement: Arrangement, column_width: int) -> dict:
    width, height = layout.width, layout.height
    direction = arrangement.direction
    if layout.column:
        column = leaf(layout.column, column_width, height, 0, 0)
        x = column_width + 1
        content = cell(layout, arrangement, width - x, height, x, 0)
        # A content split side by side, like the root, hands the root its items, as tmux itself keeps it.
        children = content["c"] if direction == "h" and "c" in content else [content]
        root = {"t": "h", "w": width, "h": height, "x": 0, "y": 0}
        root["c"] = [column] + children
    else:
        root = cell(layout, arrangement, width, height, 0, 0)
    if layout.floating:
        if "c" not in root:
            root = {"t": "h", "w": width, "h": height, "x": 0, "y": 0, "c": [root]}
        root["c"] = root["c"] + layout.floating
    return root


def cell(layout: Layout, arrangement: Arrangement, w: int, h: int, x: int, y: int):
    direction = arrangement.direction
    if len(arrangement.items) == 1 and len(arrangement.items[0]) == 1:
        return leaf(layout.leaves[arrangement.items[0][0]], w, h, x, y)
    children = []
    for item, (cw, ch, cx, cy) in zip(
        arrangement.items, split(direction, len(arrangement.items), w, h, x, y)
    ):
        if len(item) == 1:
            children.append(leaf(layout.leaves[item[0]], cw, ch, cx, cy))
            continue
        group = {"t": OTHER[direction], "w": cw, "h": ch, "x": cx, "y": cy, "c": []}
        for pane, (pw, ph, px, py) in zip(
            item, split(OTHER[direction], len(item), cw, ch, cx, cy)
        ):
            group["c"].append(leaf(layout.leaves[pane], pw, ph, px, py))
        children.append(group)
    return {"t": direction, "w": w, "h": h, "x": x, "y": y, "c": children}


def split(
    direction: str, count: int, w: int, h: int, x: int, y: int
) -> list[tuple[int, int, int, int]]:
    """count even slices of a cell, side by side for "h" or stacked for "v", with a border cell between each two;
    the first slices take the spare cells."""
    size = w if direction == "h" else h
    each, spare = divmod(size - (count - 1), count)
    slices, at = [], x if direction == "h" else y
    for k in range(count):
        length = each + (1 if k < spare else 0)
        slices.append((length, h, at, y) if direction == "h" else (w, length, x, at))
        at += length + 1
    return slices


def leaf(entry: dict, w: int, h: int, x: int, y: int) -> dict:
    """A pane's entry with new geometry, keeping its index, ID and flags."""
    kept = {
        key: value for key, value in entry.items() if key not in ("w", "h", "x", "y")
    }
    return kept | {"w": w, "h": h, "x": x, "y": y}
