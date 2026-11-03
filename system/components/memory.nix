{
  # systemd-oomd ships enabled but watches nothing until a unit opts in, so only the kernel's OOM killer acts,
  # and it waits until memory and swap are gone, after the desktop has thrashed for minutes.
  # These are Fedora's defaults (its systemd-oomd-defaults package), the split systemd-oomd(8) recommends.
  # A kill takes a whole leaf cgroup (one app scope, one Claude bubble, one tmux pane, one container), not a single process.

  # When memory and swap are both more than 90% used, kill the leaf holding the most swap.
  systemd.slices."-".sliceConfig.ManagedOOMSwap = "kill";

  # When the session's tasks are all stalled on memory for half of the time over 20 s, kill the leaf reclaiming the most.
  systemd.services."user@".serviceConfig = {
    ManagedOOMMemoryPressure = "kill";
    ManagedOOMMemoryPressureLimit = "50%";
  };
  systemd.oomd.settings.OOM.DefaultMemoryPressureDurationSec = "20s";
}
