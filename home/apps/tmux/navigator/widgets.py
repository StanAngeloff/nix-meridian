"""The status bar's widgets while the navigator is open, in place of the window list: CPU use and memory.

Read from /proc on the navigator's once-a-second wake, and handed to tmux as text with its style markup; tmux shows it
at its status-interval (5 seconds, from tmux-sensible), so the figures change calmly rather than every second.
"""

import time
from collections import deque
from dataclasses import dataclass

CPU_ICON = "\uf4bc"  # nf-oct-cpu
MEMORY_ICON = "\uefc5"  # nf-fa-memory
ICON_FG = "#6c6c6c"  # colour242
VALUE_FG = "#9e9e9e"  # colour247, the status bar's text
# A value above HOT_FRACTION turns white, not the amber or red that mean working and blocked for the Claude Code dots.
HOT_FG = "#ffffff"
HOT_FRACTION = 0.75
# CPU use is averaged over this long, the status bar's own refresh interval.
CPU_WINDOW_SECONDS = 5
CPU_FIGURE_WIDTH = len("100%")
# Swap in use is shown from this many GiB.
SHOWN_SWAP_GIB = 0.1

GIB_IN_KIB = 1024 * 1024


def cpu_times(stat: str) -> tuple[int, int]:
    """(busy, total) jiffies across all CPUs, from /proc/stat's first line; idle and iowait count as not busy."""
    fields = [int(value) for value in stat.splitlines()[0].split()[1:]]
    idle = fields[3] + fields[4]
    return sum(fields) - idle, sum(fields)


@dataclass
class Memory:
    used: float  # GiB in use: total less what is available
    total: float
    swap: float  # GiB of swap in use


def memory(meminfo: str) -> Memory:
    values = {}
    for line in meminfo.splitlines():
        key, _, rest = line.partition(":")
        if rest.split():
            values[key] = int(rest.split()[0]) / GIB_IN_KIB
    return Memory(
        values["MemTotal"] - values["MemAvailable"],
        values["MemTotal"],
        values["SwapTotal"] - values["SwapFree"],
    )


class CpuMeter:
    """CPU use over the last CPU_WINDOW_SECONDS, from samples of /proc/stat."""

    def __init__(self):
        self.samples: deque[tuple[float, int, int]] = deque()

    def add(self, now: float, busy: int, total: int) -> None:
        self.samples.append((now, busy, total))
        # Keep the newest sample at least the window old, so the average always spans the whole window.
        while len(self.samples) > 2 and now - self.samples[1][0] >= CPU_WINDOW_SECONDS:
            self.samples.popleft()

    def fraction(self) -> float | None:
        """None until there are two samples to compare."""
        if len(self.samples) < 2:
            return None
        _, first_busy, first_total = self.samples[0]
        _, last_busy, last_total = self.samples[-1]
        return (last_busy - first_busy) / max(1, last_total - first_total)


def value(fraction: float, text: str) -> str:
    colour = HOT_FG if fraction > HOT_FRACTION else VALUE_FG
    return f"#[fg={colour}]{text}"


def status_text(cpu: float | None, used: Memory) -> str:
    """The widgets in tmux style markup: the CPU icon and use, then the memory icon and use, and swap when in use."""
    # The figure sits next to its icon and the spare cells come after it, up to the four of "100%", so the group keeps
    # its width and nothing shifts as the value changes.
    if cpu is None:
        cpu_text = f"#[fg={VALUE_FG}]" + "-%".ljust(CPU_FIGURE_WIDTH)
    else:
        cpu_text = value(cpu, f"{cpu * 100:.0f}%".ljust(CPU_FIGURE_WIDTH))
    memory_text = value(used.used / used.total, f"{used.used:4.1f}/{used.total:.0f}G")
    swap_text = (
        f"#[fg={ICON_FG}] +{used.swap:.1f}G swap" if used.swap >= SHOWN_SWAP_GIB else ""
    )
    return (
        f"#[fg={ICON_FG}]{CPU_ICON} {cpu_text}   "
        f"#[fg={ICON_FG}]{MEMORY_ICON} {memory_text}{swap_text}"
    )


def read(meter: CpuMeter, now: float | None = None) -> str:
    """Samples /proc once more and returns the widgets' text."""
    with open("/proc/stat") as handle:
        busy, total = cpu_times(handle.read())
    meter.add(time.monotonic() if now is None else now, busy, total)
    with open("/proc/meminfo") as handle:
        return status_text(meter.fraction(), memory(handle.read()))
