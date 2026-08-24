import unittest

import fit


def segment(key, *forms, group=None):
    """A segment from (text, penalty) pairs, richest first."""
    return fit.Segment(
        key, group or key, tuple(fit.Form(text, penalty) for text, penalty in forms)
    )


def measure_for(segments, separator=" | "):
    """A stand-in for render's measurement: join surviving texts, count characters.

    fit takes measurement as a parameter, so its tests need no colour, no glyphs and no render.
    """

    def measure(chosen):
        texts = [s.forms[chosen[s.key]].text for s in segments]
        return len(separator.join(text for text in texts if text))

    return measure


class Richest(unittest.TestCase):
    def test_starts_every_segment_at_form_zero(self):
        segments = (segment("a", ("aaaa", 0), ("aa", 3)), segment("b", ("bbbb", 0)))
        self.assertEqual(fit.richest(segments), {"a": 0, "b": 0})


class CheapestStep(unittest.TestCase):
    def test_prefers_the_lowest_penalty_per_column_saved(self):
        # "wide" sheds 6 columns for 3 penalty (0.5); "cheap" sheds 2 for 2 (1.0).
        segments = (
            segment("wide", ("aaaaaaaa", 0), ("aa", 3)),
            segment("cheap", ("bbbb", 0), ("bb", 2)),
        )
        step = fit.cheapest_step(segments, fit.richest(segments), measure_for(segments))
        self.assertEqual(step, fit.Step("wide", 1))

    def test_steps_over_a_form_that_saves_no_columns(self):
        # Level 1 is the same width as level 0, so the only useful move is straight to the drop.
        segments = (segment("branch", ("trunk", 0), ("trunk", 5), (fit.DROP, 30)),)
        step = fit.cheapest_step(segments, fit.richest(segments), measure_for(segments))
        self.assertEqual(step, fit.Step("branch", 2))

    def test_is_none_when_nothing_can_save_a_column(self):
        segments = (segment("only", ("abc", 0)),)
        self.assertIsNone(
            fit.cheapest_step(segments, fit.richest(segments), measure_for(segments))
        )

    def test_breaks_ties_on_declared_order_then_shallowest_level(self):
        segments = (
            segment("first", ("aaaa", 0), ("aa", 2)),
            segment("second", ("bbbb", 0), ("bb", 2)),
        )
        step = fit.cheapest_step(segments, fit.richest(segments), measure_for(segments))
        self.assertEqual(step, fit.Step("first", 1))


class DegradationSequence(unittest.TestCase):
    def test_orders_every_downgrade_and_terminates(self):
        segments = (
            segment("keep", ("keeeeep", 0), ("keep", 1)),
            segment("go", ("gooooo", 0), (fit.DROP, 9)),
        )
        steps = fit.degradation_sequence(segments, measure_for(segments))
        self.assertEqual(steps, [fit.Step("keep", 1), fit.Step("go", 1)])

    def test_reaches_a_drop_hidden_behind_a_no_op_form(self):
        segments = (segment("branch", ("trunk", 0), ("trunk", 5), (fit.DROP, 30)),)
        steps = fit.degradation_sequence(segments, measure_for(segments))
        self.assertEqual(steps, [fit.Step("branch", 2)])


class Fit(unittest.TestCase):
    def setUp(self):
        self.segments = (
            segment("model", ("claude-opus-4-6", 0), ("Opus 4.6", 2), ("O4.6", 5)),
            segment("cost", ("$1.23", 0), (fit.DROP, 4)),
        )
        self.measure = measure_for(self.segments)

    def test_keeps_the_richest_forms_when_everything_fits(self):
        chosen = fit.fit(self.segments, 200, self.measure)
        self.assertEqual(chosen, {"model": 0, "cost": 0})

    def test_degrades_only_as_far_as_the_budget_demands(self):
        # "Opus 4.6 | $1.23" is 16 columns; the richest line is 23.
        chosen = fit.fit(self.segments, 16, self.measure)
        self.assertEqual(chosen, {"model": 1, "cost": 0})
        self.assertLessEqual(self.measure(chosen), 16)

    def test_selects_a_prefix_of_the_budget_independent_sequence(self):
        steps = fit.degradation_sequence(self.segments, self.measure)
        for budget in range(4, 30):
            chosen = fit.fit(self.segments, budget, self.measure)
            replayed = fit.richest(self.segments)
            for step in steps:
                if replayed == chosen:
                    break
                replayed[step.key] = step.level
            self.assertEqual(
                replayed, chosen, f"budget {budget} is not a prefix of the sequence"
            )

    def test_narrowing_never_restores_a_segment(self):
        previous = None
        for budget in range(40, 3, -1):
            chosen = fit.fit(self.segments, budget, self.measure)
            if previous is not None:
                for key, level in chosen.items():
                    self.assertGreaterEqual(
                        level, previous[key], f"{key} got richer at {budget}"
                    )
            previous = chosen

    def test_returns_the_tersest_line_rather_than_looping_when_nothing_fits(self):
        chosen = fit.fit(self.segments, 1, self.measure)
        self.assertEqual(chosen, {"model": 2, "cost": 1})
        self.assertIsNone(fit.cheapest_step(self.segments, chosen, self.measure))
