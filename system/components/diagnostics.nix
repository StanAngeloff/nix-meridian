{
  # Electron apps like Typora have multi-gigabyte virtual address spaces and ship no debug symbols.
  # systemd-coredump reads the full image before deciding to truncate, so a single crash burns
  # 30+ seconds of CPU and 90+ GB of disk I/O for a dump that resolves zero stack frames.
  systemd.coredump.settings.Coredump = {
    Storage = "none";
    ProcessSizeMax = 0;
  };
}
