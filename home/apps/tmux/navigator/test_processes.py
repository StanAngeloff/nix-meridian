import os
import tempfile
import unittest

import processes


def make_process(root: str, pid: str, name: str, child_pids: list[str]) -> None:
    os.makedirs(f"{root}/{pid}/task/{pid}")
    with open(f"{root}/{pid}/comm", "w") as handle:
        handle.write(name + "\n")
    with open(f"{root}/{pid}/task/{pid}/children", "w") as handle:
        handle.write(" ".join(child_pids) + (" " if child_pids else ""))


class TmuxClientTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = self.directory.name

    def tearDown(self):
        self.directory.cleanup()

    def test_finds_a_client_started_by_a_script_in_the_shell(self):
        make_process(self.root, "10", "zsh", ["11"])
        make_process(self.root, "11", "bash", ["12"])
        make_process(self.root, "12", "tmux: client", [])
        self.assertTrue(processes.runs_tmux_client("10", self.root))

    def test_a_shell_running_something_else_has_none(self):
        make_process(self.root, "20", "zsh", ["21"])
        make_process(self.root, "21", "nvim", [])
        self.assertFalse(processes.runs_tmux_client("20", self.root))

    def test_a_process_gone_meanwhile_counts_as_none(self):
        make_process(self.root, "30", "zsh", ["31"])
        self.assertFalse(processes.runs_tmux_client("30", self.root))
        self.assertFalse(processes.runs_tmux_client("", self.root))


if __name__ == "__main__":
    unittest.main()
