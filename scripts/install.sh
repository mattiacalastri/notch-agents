#!/bin/bash
# Install Notch Agenti: build the app, connect it to Claude Code, start it at login.
# Usage: bash scripts/install.sh        (run it again after a `git pull` to update)
set -euo pipefail
cd "$(dirname "$0")/.."

say() { printf '\033[1m▸ %s\033[0m\n' "$1"; }
die() { printf '\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

[ "$(uname)" = "Darwin" ] || die "Notch Agenti gira solo su macOS."
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 14 ] || die "Serve macOS 14 (Sonoma) o successivo."
command -v swift > /dev/null || die "Manca Swift: installa gli strumenti da riga di comando con  xcode-select --install"
command -v python3 > /dev/null || die "Manca python3: installa gli strumenti da riga di comando con  xcode-select --install"
command -v claude > /dev/null || echo "  (claude non è nel PATH: installa Claude Code, poi rilancia questo script)"

HOME_DIR="$HOME/.notch-agenti"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LABEL="com.mattiacalastri.notch-agenti"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
APP="$HOME/Applications/Notch Agenti.app"

say "Compilo l'app (la prima volta ci vuole un minuto)"
bash scripts/build_app.sh

say "Collego Claude Code"
mkdir -p "$HOME_DIR/run"
cp hooks/notch-agenti-hook.sh hooks/notch-agenti-statusline.sh "$HOME_DIR/"
chmod +x "$HOME_DIR"/*.sh
# The app starts outside your shell: it needs to know where claude and codex are.
{
  echo "CLAUDE_BIN=$(command -v claude || true)"
  echo "CODEX_BIN=$(command -v codex || true)"
  echo "PATH=$PATH"
  echo "CLAUDE_CONFIG_DIR=$CLAUDE_DIR"
} > "$HOME_DIR/env"
python3 scripts/claude_settings.py install "$CLAUDE_DIR/settings.json" \
  "$HOME_DIR/notch-agenti-hook.sh" "$HOME_DIR/notch-agenti-statusline.sh" "$HOME_DIR/statusline-previous"

say "Installo l'app in ~/Applications e la avvio al login"
launchctl bootout "gui/$(id -u)/$LABEL" 2> /dev/null || true
pkill -x NotchAgenti 2> /dev/null || true
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
rm -rf "$APP"
cp -R "dist/Notch Agenti.app" "$APP"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$APP/Contents/MacOS/NotchAgenti</string></array>
  <key>RunAtLoad</key><true/>
  <!-- restarts after a crash; «Esci» from the menu exits 0 and stays closed -->
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PLIST
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo
say "Fatto. Porta il mouse sul notch."
echo "  Le sessioni di Claude Code già aperte compaiono quando le riavvii; le nuove subito."
echo "  Per toglierla:  bash scripts/uninstall.sh"
