#!/bin/bash
# Notch Agenti — Claude Code status line.
#
# Claude Code hands the status line a JSON with the account limits (`rate_limits`,
# on Pro and Max plans). This keeps the latest one for the notch in
# ~/.notch-agenti/run/statusline.json, then draws the status line: the one you had
# before installing (saved in ~/.notch-agenti/statusline-previous), or a simple one.

RUN="${NOTCH_AGENTI_RUN:-$HOME/.notch-agenti/run}"
input="$(cat)"
if mkdir -p "$RUN" 2>/dev/null && printf '%s' "$input" > "$RUN/statusline.json.$$" 2>/dev/null; then
  mv -f "$RUN/statusline.json.$$" "$RUN/statusline.json" 2>/dev/null
fi

previous="$HOME/.notch-agenti/statusline-previous"
if [ -s "$previous" ]; then
  printf '%s' "$input" | /bin/sh -c "$(cat "$previous")"
  exit $?
fi

field() {
  [[ "$input" =~ \"$1\"[[:space:]]*:[[:space:]]*\"(([^\"\\]|\\.)*)\" ]] && printf '%s' "${BASH_REMATCH[1]}"
}
model="$(field display_name)"
dir="$(field current_dir)"; [ -z "$dir" ] && dir="$(field cwd)"
printf '%s · %s' "${model:-Claude}" "${dir##*/}"
