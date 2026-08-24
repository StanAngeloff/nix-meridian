"""Choosing which form of each status line segment to show, for a given number of columns.

Every segment offers an ordered list of forms, richest first, each carrying a penalty for how much
using it costs in information. The fitter spends the cheapest penalty per column saved, repeatedly,
and drops a segment only once it has no shorter form left.

Nothing here knows about JSON, colour, separators or terminals. Widths arrive through the `measure`
callable the caller supplies, which is what keeps the layout rules in exactly one place; see
render.py.
"""

from dataclasses import dataclass

# A form with no text. Rendering skips it, so this is how a segment declares that it can be dropped.
DROP = ""


@dataclass(frozen=True)
class Form:
    text: str
    penalty: int


@dataclass(frozen=True)
class Segment:
    key: str
    # Segments sharing a group render space-separated inside one separator-delimited run, which is
    # how the two rate limits stay a single visual unit.
    group: str
    forms: tuple


@dataclass(frozen=True)
class Step:
    key: str
    level: int


def richest(segments):
    """The starting choice: every segment at its richest form."""
    return {segment.key: 0 for segment in segments}


def cheapest_step(segments, chosen, measure):
    """The downgrade with the lowest penalty per column saved, or None when none saves a column.

    Every deeper level is considered, not only the next one. A form can be shorter in principle and
    the same width in practice -- truncating a branch name already under the limit changes nothing --
    and a next-level-only search would either divide by zero on such a form or keep picking it
    without making progress, never reaching the drop behind it.
    """
    base_width = measure(chosen)
    best_step = None
    best_ratio = None
    for segment in segments:
        current_level = chosen[segment.key]
        for level in range(current_level + 1, len(segment.forms)):
            candidate = dict(chosen)
            candidate[segment.key] = level
            saved_columns = base_width - measure(candidate)
            if saved_columns <= 0:
                continue
            spent = segment.forms[level].penalty - segment.forms[current_level].penalty
            ratio = spent / saved_columns
            # A strict comparison keeps the first candidate found, so ties fall to declared segment
            # order and then to the shallowest level, making the sequence reproducible.
            if best_ratio is None or ratio < best_ratio:
                best_step = Step(segment.key, level)
                best_ratio = ratio
    return best_step


def degradation_sequence(segments, measure):
    """Every downgrade, in the order it should be spent.

    The order does not depend on any budget: a narrower terminal only advances further along this one
    sequence. Monotonicity follows for free, and the sequence itself is the behavioural contract.
    """
    chosen = richest(segments)
    steps = []
    while True:
        step = cheapest_step(segments, chosen, measure)
        if step is None:
            return steps
        chosen[step.key] = step.level
        steps.append(step)


def fit(segments, budget, measure):
    """The form of each segment that fits `budget` columns, as a {key: level} mapping.

    When the sequence runs out and the line still overflows, the tersest forms are returned and
    Claude Code truncates -- a floor, not a failure.
    """
    chosen = richest(segments)
    for step in degradation_sequence(segments, measure):
        if measure(chosen) <= budget:
            break
        chosen[step.key] = step.level
    return chosen
