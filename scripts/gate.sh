#!/usr/bin/env bash
# PreToolUse hook. Reads the cached 5-hour utilization percent and the per-project
# policy, then:
#   >= HARD  -> block the tool call (exit 2)
#   >= SOFT  -> inject a "wrap up and save" nudge (non-blocking), rate-limited
#   otherwise / no data / stale / disabled -> allow (exit 0, fail open)
# $1 is the project dir, passed by hooks.json as ${CLAUDE_PROJECT_DIR}.

SD="$(cd "$(dirname "$0")" && pwd)"; . "$SD/common.sh" "$1"

gate_off && exit 0
[ -f "$CACHE" ] || exit 0

age=$(( $(date +%s) - $(stat -c %Y "$CACHE" 2>/dev/null || echo 0) ))
[ "$age" -gt "$STALE" ] && exit 0

pct=$(tr -dc '0-9.' < "$CACHE"); five=${pct%.*}
case "$five" in ''|*[!0-9]*) exit 0;; esac

if [ "$five" -ge "$HARD" ]; then
  echo "BLOCKED by usage gate ($SCOPE policy for $PROJECT_DIR): 5-hour window at ${pct}% (hard limit ${HARD}%). Work is paused until usage drops below ${HARD}% or the window resets. Override now: touch \"$PROJ_OFF\"" >&2
  exit 2
fi

if [ "$five" -ge "$SOFT" ]; then
  wage=$(( $(date +%s) - $(stat -c %Y "$WARN" 2>/dev/null || echo 0) ))
  if [ "$wage" -ge "$SOFT_REPEAT" ]; then
    touch "$WARN"
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"Usage gate: 5-hour window at %s%% (soft limit %s%%, hard stop %s%%). Wrap up and save progress (e.g. run /bob) before the hard limit blocks tool calls."}}\n' "$pct" "$SOFT" "$HARD"
  fi
  exit 0
fi

rm -f "$WARN" 2>/dev/null   # back below the soft limit: reset the nudge timer
exit 0
