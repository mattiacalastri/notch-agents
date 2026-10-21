#!/bin/bash
# Installs and uninstalls into a throwaway home, with launchctl and pkill stubbed out,
# and checks that Claude Code's settings come back exactly as they were.
# Run: bash Tests/install_test.sh   (it builds the app: about a minute the first time)
set -u
cd "$(dirname "$0")/.."
FH="$(mktemp -d)"
STUB="$(mktemp -d)"
trap 'rm -rf "$FH" "$STUB"' EXIT
printf '#!/bin/sh\nexit 0\n' > "$STUB/launchctl"
cp "$STUB/launchctl" "$STUB/pkill"
chmod +x "$STUB/launchctl" "$STUB/pkill"
mkdir -p "$FH/.claude"
before='{"statusLine": {"type": "command", "command": "echo mine"}, "model": "opus"}'
printf '%s' "$before" > "$FH/.claude/settings.json"
fails=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected «$2», got «$3»"; fails=$((fails + 1)); fi; }

HOME="$FH" PATH="$STUB:$PATH" bash scripts/install.sh > "$FH/install.log" 2>&1
check "install exits 0" "0" "$?"
check "the app is in ~/Applications" "yes" "$([ -x "$FH/Applications/Notch Agenti.app/Contents/MacOS/NotchAgenti" ] && echo yes)"
check "the login item is a valid plist" "yes" "$(plutil -lint "$FH/Library/LaunchAgents/com.mattiacalastri.notch-agenti.plist" > /dev/null && echo yes)"
check "the hook is in place" "yes" "$([ -x "$FH/.notch-agenti/notch-agenti-hook.sh" ] && echo yes)"
check "the env file knows the PATH" "yes" "$(grep -q '^PATH=/' "$FH/.notch-agenti/env" && echo yes)"
check "your status line is saved" "echo mine" "$(cat "$FH/.notch-agenti/statusline-previous")"
check "settings point to the hook" "yes" "$(grep -q 'notch-agenti-hook.sh' "$FH/.claude/settings.json" && echo yes)"

HOME="$FH" PATH="$STUB:$PATH" bash scripts/uninstall.sh > /dev/null 2>&1
same="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])) == json.loads(sys.argv[2]))' "$FH/.claude/settings.json" "$before")"
check "uninstall gives the settings back" "True" "$same"
check "uninstall removes the app" "no" "$([ -e "$FH/Applications/Notch Agenti.app" ] && echo yes || echo no)"
check "uninstall removes ~/.notch-agenti" "no" "$([ -e "$FH/.notch-agenti" ] && echo yes || echo no)"

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; cat "$FH/install.log"; exit 1; }
