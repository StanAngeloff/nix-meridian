import unittest

import widgets

MEMINFO = """MemTotal:       32505856 kB
MemFree:         1048576 kB
MemAvailable:   19173376 kB
SwapTotal:      33554432 kB
SwapFree:       16252928 kB
"""


class ReadTest(unittest.TestCase):
    def test_cpu_times_count_idle_and_iowait_as_not_busy(self):
        stat = "cpu  100 0 50 800 50 0 0 0 0 0\ncpu0 1 2 3 4 5 6 7 8 9 10\n"
        self.assertEqual(widgets.cpu_times(stat), (150, 1000))

    def test_memory_in_use_is_total_less_available(self):
        used = widgets.memory(MEMINFO)
        self.assertAlmostEqual(used.used, (32505856 - 19173376) / widgets.GIB_IN_KIB)
        self.assertAlmostEqual(used.total, 31.0, places=1)
        self.assertAlmostEqual(used.swap, 16.5, places=1)


class CpuMeterTest(unittest.TestCase):
    def test_no_figure_until_two_samples(self):
        meter = widgets.CpuMeter()
        meter.add(0.0, 0, 0)
        self.assertIsNone(meter.fraction())

    def test_the_average_spans_the_last_five_seconds(self):
        meter = widgets.CpuMeter()
        meter.add(0.0, 0, 0)
        for second in range(1, 11):
            # Fully busy for the first five seconds, idle after.
            busy = min(second, 5) * 100
            meter.add(float(second), busy, second * 100)
        self.assertEqual(meter.fraction(), 0.0)
        self.assertLessEqual(len(meter.samples), widgets.CPU_WINDOW_SECONDS + 2)


class TextTest(unittest.TestCase):
    def test_icons_values_and_swap_in_use(self):
        text = widgets.status_text(0.23, widgets.memory(MEMINFO))
        self.assertIn(widgets.CPU_ICON + " #[fg=#9e9e9e] 23%", text)
        self.assertIn(widgets.MEMORY_ICON + " #[fg=#9e9e9e]12.7/31G", text)
        self.assertIn("+16.5G swap", text)

    def test_the_figure_is_right_aligned_and_the_widget_keeps_its_width(self):
        memory = widgets.Memory(used=2.0, total=31.0, swap=0.0)
        low, full = widgets.status_text(0.03, memory), widgets.status_text(1.0, memory)
        self.assertIn(widgets.CPU_ICON + " #[fg=#9e9e9e]  3%", low)
        self.assertEqual(
            low.index(widgets.MEMORY_ICON), full.index(widgets.MEMORY_ICON)
        )

    def test_each_widget_sits_on_a_lighter_patch_and_the_profile_comes_first(self):
        memory = widgets.Memory(used=2.0, total=31.0, swap=0.0)
        text = widgets.status_text(0.1, memory, profile="personal/2")
        patches = text.split("#[bg=default]")
        self.assertEqual(text.count(f"#[bg={widgets.PATCH_BG}] "), 3)
        self.assertIn(widgets.PROFILE_ICON + " #[fg=#9e9e9e]personal/2", patches[0])
        self.assertIn(widgets.CPU_ICON, patches[1])
        self.assertIn(widgets.MEMORY_ICON, patches[2])

    def test_no_profile_no_profile_widget(self):
        memory = widgets.Memory(used=2.0, total=31.0, swap=0.0)
        self.assertNotIn(widgets.PROFILE_ICON, widgets.status_text(0.1, memory))

    def test_a_high_value_turns_white(self):
        text = widgets.status_text(0.9, widgets.memory(MEMINFO))
        self.assertIn("#[fg=#ffffff] 90%", text)

    def test_no_swap_in_use_is_left_out_and_no_cpu_figure_shows_a_dash(self):
        no_swap = widgets.Memory(used=2.0, total=31.0, swap=0.0)
        text = widgets.status_text(None, no_swap)
        self.assertNotIn("swap", text)
        self.assertIn("  -%", text)


if __name__ == "__main__":
    unittest.main()
