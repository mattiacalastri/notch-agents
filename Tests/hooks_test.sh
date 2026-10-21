#!/bin/bash
# Tests for the two shell scripts in hooks/. Run: bash Tests/hooks_test.sh
# The hook finds its terminal through its ancestors, so it runs under `script`, which gives it one.
set -u
cd "$(dirname "$0")/.."
HOOK="$PWD/hooks/notch-agenti-hook.sh"
LINE="$PWD/hooks/notch-agenti-statusline.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export NOTCH_AGENTI_RUN="$T/run"
fails=0

check() {   # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected «$2», got «$3»"; fails=$((fails + 1)); fi
}

in_tty() {   # in_tty <payload>: runs the hook with a terminal, the way Claude Code does
  printf '%s' "$1" > "$T/payload.json"
  script -q /dev/null /bin/bash -c "\"$HOOK\" < \"$T/payload.json\"" < /dev/null > /dev/null
}

in_tty '{"session_id":"s","transcript_path":"/tmp/x y/s.jsonl","cwd":"/Users/a/my projects/my-app","hook_event_name":"SessionStart"}'
check "SessionStart writes idle" "idle" "$(cat "$NOTCH_AGENTI_RUN"/state_*.txt)"
check "the name is the project folder" "my-app" "$(cat "$NOTCH_AGENTI_RUN"/name_*.txt)"
check "the transcript path is kept" "/tmp/x y/s.jsonl" "$(cat "$NOTCH_AGENTI_RUN"/transcript_*.txt)"

in_tty '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"/elsewhere"}'
check "a tool call is working" "working" "$(cat "$NOTCH_AGENTI_RUN"/state_*.txt)"
check "the name stays the first folder" "my-app" "$(cat "$NOTCH_AGENTI_RUN"/name_*.txt)"

in_tty '{"hook_event_name":"Notification","message":"Claude needs your permission to use Bash"}'
check "a permission request is notify" "notify" "$(cat "$NOTCH_AGENTI_RUN"/state_*.txt)"

in_tty '{"hook_event_name":"Stop"}'
in_tty '{"hook_event_name":"Notification","message":"Claude is waiting for your input"}'
check "the idle reminder keeps a finished turn finished" "idle" "$(cat "$NOTCH_AGENTI_RUN"/state_*.txt)"

in_tty '{"hook_event_name":"SessionEnd","reason":"exit"}'
check "SessionEnd removes the terminal's files" "0" "$(ls "$NOTCH_AGENTI_RUN" | wc -l | tr -d ' ')"

in_tty '{"hook_event_name":"SubagentStop"}'
check "an event it does not know writes nothing" "0" "$(ls "$NOTCH_AGENTI_RUN" | wc -l | tr -d ' ')"

json='{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/a/b/proj"},"rate_limits":{"five_hour":{"used_percentage":3,"resets_at":1}}}'
out="$(printf '%s' "$json" | HOME="$T" "$LINE")"
check "the status line draws model and folder" "Opus · proj" "$out"
check "the status line keeps its input for the notch" "$json" "$(cat "$NOTCH_AGENTI_RUN/statusline.json")"

mkdir -p "$T/.notch-agenti"
printf '%s' 'cat > /dev/null; echo previous line' > "$T/.notch-agenti/statusline-previous"
check "the previous status line still draws" "previous line" "$(printf '{}' | HOME="$T" "$LINE")"

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
