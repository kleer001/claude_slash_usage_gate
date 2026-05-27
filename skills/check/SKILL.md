---
name: check
description: Report Claude.ai 5-hour and 7-day rate-limit usage with reset countdowns, and view or control the usage gate (a soft "wrap up" nudge plus a hard tool-call block on the 5-hour window). Use when the user invokes /usage:check (optionally with on / off / soft N / hard N), asks how much of their usage limit / 5-hour window / weekly quota is left or how long until it resets, or wants to enable, disable, or adjust the soft/hard usage gate.
allowed-tools: Bash
argument-hint: "[on | off | soft N | hard N]"
---

# /usage:check

Reports Claude.ai rate-limit usage and controls this plugin's **usage gate** — a `PreToolUse`
hook that, based on the 5-hour window, injects a "wrap up and save" nudge at the **soft** limit
and blocks tool calls at the **hard** limit. State lives in `~/.claude/usage-gate/`: `config`
(`SOFT=`/`HARD=` percentages), `off` (kill switch), `cache` (the percent the hook reads).

Choose the action from the argument:
- **no argument** → show usage + gate status
- **`on`** / **`off`** → enable / disable the gate (remove / create the kill switch)
- **`soft N`** / **`soft off`** → set / clear the soft (nudge) limit, integer 1–100
- **`hard N`** / **`hard off`** → set / clear the hard (block) limit, integer 1–100

Relay command output to the user verbatim. If a line starts with `check:`, report it plainly and
stop — do not retry, fall back to another source, or guess a number. `HTTP 401` means the stored
OAuth token expired; `HTTP 429` means the usage endpoint is rate-limiting.

## Status (no argument)

```bash
GD="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/usage-gate"
CRED="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
TOKEN=$(jq -r '.claudeAiOauth.accessToken // empty' "$CRED" 2>/dev/null)
[ -z "$TOKEN" ] && { echo "check: no OAuth token in $CRED"; exit 1; }

resp=$(curl -sS -m 15 -w $'\n%{http_code}' https://api.anthropic.com/api/oauth/usage \
  -H "Authorization: Bearer $TOKEN" -H "anthropic-beta: oauth-2025-04-20" -H "User-Agent: claude-code/2.1")
code=${resp##*$'\n'}; body=${resp%$'\n'*}
[ "$code" != "200" ] && { echo "check: usage API HTTP $code: $body"; exit 1; }

now=$(date +%s)
echo "Usage:"
printf '%s' "$body" | jq -r '
  "5-hour\t\(.five_hour.utilization)\t\(.five_hour.resets_at)",
  "7-day\t\(.seven_day.utilization)\t\(.seven_day.resets_at)"' |
while IFS=$'\t' read -r label util reset; do
  pct=${util%.*}
  if [ "$reset" != "null" ] && [ -n "$reset" ]; then
    secs=$(( $(date -d "$reset" +%s) - now ))
    printf '  %-7s %3s%%  (resets in %dh %dm)\n' "$label" "$pct" "$(( secs/3600 ))" "$(( (secs%3600)/60 ))"
  else
    printf '  %-7s %3s%%\n' "$label" "$pct"
  fi
done

five=$(printf '%s' "$body" | jq -r '.five_hour.utilization // 0'); five=${five%.*}
SOFT=; HARD=; [ -f "$GD/config" ] && . "$GD/config"
state="ENABLED"; [ -f "$GD/off" ] && state="DISABLED"
echo "Gate:  $state   soft=${SOFT:-off}  hard=${HARD:-off}"
if [ "$state" = ENABLED ]; then
  if [ -n "$HARD" ] && [ "${five:-0}" -ge "$HARD" ] 2>/dev/null; then
    echo "       -> HARD BLOCKING now (5h ${five}% >= ${HARD}%)"
  elif [ -n "$SOFT" ] && [ "${five:-0}" -ge "$SOFT" ] 2>/dev/null; then
    echo "       -> soft nudging (5h ${five}% >= ${SOFT}%, below hard ${HARD:-none})"
  else
    echo "       -> not gating (5h ${five}% below limits)"
  fi
fi
```

## Enable (`on`) / Disable (`off`)

```bash
GD="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/usage-gate"; mkdir -p "$GD"
rm -f "$GD/off" && echo "Usage gate ENABLED."        # for: on
# touch "$GD/off" && echo "Usage gate DISABLED (re-enable with /usage:check on)."   # for: off
```

## Set a limit (`soft N` / `hard N`)

Validate N is an integer 1–100 (or the literal `off` to clear), then run this, substituting
`KEY` with `SOFT` or `HARD` and `N` with the value. For `off`, omit the final append line so the
key is removed (that limit becomes inactive):

```bash
GD="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/usage-gate"; F="$GD/config"; mkdir -p "$GD"; touch "$F"
old=$(sed -n 's/^KEY=\(.*\)/\1/p' "$F")
grep -v '^KEY=' "$F" > "$F.tmp" && mv "$F.tmp" "$F"
printf 'KEY=%s\n' "N" >> "$F"
echo "KEY limit set to N% (was ${old:-off})."
```
