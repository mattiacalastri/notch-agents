#!/bin/bash
# Remove Notch Agenti: the app, the start at login, and what it added to Claude Code.
# Your status line comes back as it was. Usage: bash scripts/uninstall.sh
set -uo pipefail
cd "$(dirname "$0")/.."

HOME_DIR="$HOME/.notch-agenti"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LABEL="com.mattiacalastri.notch-agenti"

launchctl bootout "gui/$(id -u)/$LABEL" 2> /dev/null
pkill -x NotchAgenti 2> /dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$HOME/Applications/Notch Agenti.app"
if [ -f "$CLAUDE_DIR/settings.json" ]; then
  python3 scripts/claude_settings.py uninstall "$CLAUDE_DIR/settings.json" "$HOME_DIR/statusline-previous"
fi
rm -rf "$HOME_DIR"
echo "Notch Agenti rimossa. Claude Code è tornato com'era (una copia delle impostazioni è in $CLAUDE_DIR)."
