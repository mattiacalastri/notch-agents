#!/bin/bash
# Notch Agenti — Claude Code hook.
#
# Claude Code runs this on every session event and passes a JSON payload on stdin.
# It writes, for the terminal the session runs in (its tty):
#   state_<tty>.txt       working | notify | idle
#   name_<tty>.txt        the project folder, the name shown on the tile
#   transcript_<tty>.txt  the transcript path, to read what the session does or asks
# into ~/.notch-agenti/run. It never blocks Claude Code: any failure exits 0 silently.
set -u

RUN="${NOTCH_AGENTI_RUN:-$HOME/.notch-agenti/run}"
mkdir -p "$RUN" 2>/dev/null || exit 0

payload="$(cat 2>/dev/null)"
field() {
  [[ "$payload" =~ \"$1\"[[:space:]]*:[[:space:]]*\"(([^\"\\]|\\.)*)\" ]] && printf '%s' "${BASH_REMATCH[1]}"
}

event="$(field hook_event_name)"
case "$event" in
  UserPromptSubmit|PreToolUse|PostToolUse) state="working" ;;
  Notification)
    # «Claude is waiting for your input» comes a minute after a finished turn: still finished
    case "$(field message)" in
      *"waiting for your input"*) state="idle" ;;
      *) state="notify" ;;
    esac ;;
  Stop|SessionStart) state="idle" ;;
  SessionEnd) state="gone" ;;
  *) exit 0 ;;
esac

# The hook has no terminal of its own, but an ancestor (the `claude` process) does.
resolve_tty() {
  local p=$$ ppid tty
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    set -- $(ps -o ppid=,tty= -p "$p" 2>/dev/null)
    ppid="${1:-}"; tty="${2:-}"
    [ -z "$ppid" ] && break
    case "$tty" in ttys*) printf '%s' "$tty"; return 0 ;; esac
    p="$ppid"; [ "${p:-0}" -le 1 ] && break
  done
  return 1
}
tty="$(resolve_tty)" || exit 0

if [ "$state" = "gone" ]; then
  rm -f "$RUN/state_$tty.txt" "$RUN/name_$tty.txt" "$RUN/transcript_$tty.txt"
  exit 0
fi

printf '%s' "$state" > "$RUN/state_$tty.txt" 2>/dev/null

transcript="$(field transcript_path)"
if [ -n "$transcript" ]; then
  old="$(cat "$RUN/transcript_$tty.txt" 2>/dev/null)"
  [ "$old" != "$transcript" ] && printf '%s' "$transcript" > "$RUN/transcript_$tty.txt" 2>/dev/null
fi

if [ "$event" = "SessionStart" ] || [ ! -s "$RUN/name_$tty.txt" ]; then
  cwd="$(field cwd)"
  [ -z "$cwd" ] && cwd="$PWD"
  if [ "$cwd" = "$HOME" ] || [ "$cwd" = "/" ]; then name="Terminale"; else name="${cwd##*/}"; fi
  printf '%s' "$name" > "$RUN/name_$tty.txt" 2>/dev/null
fi
exit 0
