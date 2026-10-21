#!/usr/bin/env python3
"""Add or remove Notch Agenti in Claude Code's settings.json, leaving the rest untouched.

  python3 scripts/claude_settings.py install   <settings.json> <hook> <statusline> <previous-file>
  python3 scripts/claude_settings.py uninstall <settings.json> <previous-file>

install: adds the hook to the session events (once: running it again changes nothing) and
sets the status line to Notch Agenti's; a status line you already had is saved in
<previous-file> and keeps drawing. A copy of settings.json is kept beside it first.
uninstall: removes exactly what install added and gives your status line back.
"""
import json
import shutil
import sys
import time
from pathlib import Path

EVENTS = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop", "SessionEnd"]
TOOL_EVENTS = {"PreToolUse", "PostToolUse"}
MARK = "notch-agenti"


def ours(entry):
    return any(MARK in (h.get("command") or "") for h in entry.get("hooks", []))


def load(path):
    """The settings as they are. A file that is not a JSON object stops everything:
    rewriting it would lose what is in it."""
    if not path.exists() or not path.read_text().strip():
        return {}
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as e:
        sys.exit(f"{path} non è JSON valido (riga {e.lineno}): correggilo e rilancia, così com'è non lo tocco.")
    if not isinstance(data, dict):
        sys.exit(f"{path} non contiene un oggetto JSON: correggilo e rilancia, così com'è non lo tocco.")
    return data


def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        shutil.copy2(path, path.with_name(f"{path.name}.bak-notch-agenti-{time.strftime('%Y%m%d-%H%M%S')}"))
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    tmp.replace(path)


def install(settings, hook, statusline, previous):
    data = load(settings)
    hooks = data.setdefault("hooks", {})
    command = f'"{hook}"'
    for event in EVENTS:
        entries = [e for e in hooks.get(event, []) if not ours(e)]
        entry = {"hooks": [{"type": "command", "command": command, "timeout": 5}]}
        if event in TOOL_EVENTS:
            entry = {"matcher": "*", **entry}
        hooks[event] = entries + [entry]
    current = data.get("statusLine") or {}
    if current.get("command") and MARK not in current["command"]:
        previous.parent.mkdir(parents=True, exist_ok=True)
        previous.write_text(current["command"])
    data["statusLine"] = {"type": "command", "command": f'"{statusline}"'}
    if "padding" in current:
        data["statusLine"]["padding"] = current["padding"]
    save(settings, data)


def uninstall(settings, previous):
    data = load(settings)
    hooks = data.get("hooks", {})
    for event in list(hooks):
        kept = [e for e in hooks[event] if not ours(e)]
        if kept:
            hooks[event] = kept
        else:
            del hooks[event]
    if not hooks:
        data.pop("hooks", None)
    line = data.get("statusLine") or {}
    if MARK in (line.get("command") or ""):
        if previous.exists() and previous.read_text().strip():
            data["statusLine"] = {"type": "command", "command": previous.read_text().strip()}
            if "padding" in line:
                data["statusLine"]["padding"] = line["padding"]
        else:
            data.pop("statusLine", None)
    save(settings, data)


if __name__ == "__main__":
    if len(sys.argv) == 6 and sys.argv[1] == "install":
        install(Path(sys.argv[2]), sys.argv[3], sys.argv[4], Path(sys.argv[5]))
    elif len(sys.argv) == 4 and sys.argv[1] == "uninstall":
        uninstall(Path(sys.argv[2]), Path(sys.argv[3]))
    else:
        sys.exit(__doc__)
