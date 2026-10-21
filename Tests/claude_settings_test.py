#!/usr/bin/env python3
"""Tests for scripts/claude_settings.py. Run: python3 Tests/claude_settings_test.py"""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
import claude_settings as cs  # noqa: E402

HOOK = "/Users/x/.notch-agenti/notch-agenti-hook.sh"
LINE = "/Users/x/.notch-agenti/notch-agenti-statusline.sh"


class SettingsTests(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.settings = self.dir / "settings.json"
        self.previous = self.dir / "statusline-previous"
        self.mine = {
            "model": "opus",
            "permissions": {"allow": ["Bash(ls:*)"]},
            "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "say done"}]}]},
            "statusLine": {"type": "command", "command": "~/my-line.sh", "padding": 1},
        }
        self.settings.write_text(json.dumps(self.mine))

    def read(self):
        return json.loads(self.settings.read_text())

    def test_install_adds_the_hook_and_keeps_everything_else(self):
        cs.install(self.settings, HOOK, LINE, self.previous)
        s = self.read()
        self.assertEqual(s["model"], "opus")
        self.assertEqual(s["permissions"], self.mine["permissions"])
        self.assertEqual(s["hooks"]["Stop"][0]["hooks"][0]["command"], "say done")
        for event in cs.EVENTS:
            self.assertTrue(any(cs.ours(e) for e in s["hooks"][event]), event)
        self.assertEqual(s["hooks"]["PreToolUse"][-1]["matcher"], "*")
        self.assertIn(LINE, s["statusLine"]["command"])
        self.assertEqual(s["statusLine"]["padding"], 1)
        self.assertEqual(self.previous.read_text(), "~/my-line.sh")
        self.assertTrue(list(self.dir.glob("settings.json.bak-notch-agenti-*")), "a copy is kept")

    def test_installing_twice_changes_nothing(self):
        cs.install(self.settings, HOOK, LINE, self.previous)
        once = self.read()
        cs.install(self.settings, HOOK, LINE, self.previous)
        self.assertEqual(self.read(), once)
        self.assertEqual(self.previous.read_text(), "~/my-line.sh", "our own line is never saved as yours")

    def test_uninstall_gives_back_what_there_was(self):
        cs.install(self.settings, HOOK, LINE, self.previous)
        cs.uninstall(self.settings, self.previous)
        self.assertEqual(self.read(), self.mine)

    def test_a_fresh_claude_code_without_settings(self):
        self.settings.unlink()
        cs.install(self.settings, HOOK, LINE, self.previous)
        self.assertIn(LINE, self.read()["statusLine"]["command"])
        self.assertFalse(self.previous.exists())
        cs.uninstall(self.settings, self.previous)
        self.assertEqual(self.read(), {})


if __name__ == "__main__":
    unittest.main()
