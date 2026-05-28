---
name: check
description: Report Claude.ai 5-hour and 7-day rate-limit usage with reset countdowns, and view or control the usage gate (a soft "wrap up" nudge plus a hard tool-call block on the 5-hour window). The gate's thresholds and on/off are per-project (with a global default fallback). Use when the user invokes /usage:check (optionally with on / off / soft N / hard N, plus --global), asks how much of their usage limit / 5-hour window / weekly quota is left or how long until it resets, or wants to enable, disable, or adjust the soft/hard usage gate.
allowed-tools: Bash
argument-hint: "[on | off | soft N | hard N] [--global]"
---

# /usage:check

Human reference (commands, status fields, state files, escape hatch, gotchas): `MANUAL.md` in
this directory.

Reports Claude.ai rate-limit usage and controls this plugin's **usage gate** — a `PreToolUse`
hook that, based on the 5-hour window, injects a "wrap up and save" nudge at the **soft** limit
and blocks tool calls at the **hard** limit.

**Scope model.** The 5-hour usage `cache` is account-wide, so it is global. The gate **policy**
(soft/hard thresholds and the off kill switch) is **per project**: it resolves from
`~/.claude/usage-gate/projects/<slug-of-project-path>/{config,off}`, falling back to the global
`~/.claude/usage-gate/{config,off}`, then to built-in defaults (`soft 80`, `hard 90`). The gate
is disabled if *either* the project or the global kill switch exists. Commands write the
**current project's** policy by default; pass **`--global`** to set the global fallback instead.

The project is identified by `$CLAUDE_PROJECT_DIR` when set, else the current working directory —
so run the command from within the project you mean to configure.

Choose the action from the argument:
- **no argument** → show usage + effective gate status for this project
- **`on`** / **`off`** → enable / disable the gate for this project (or global with `--global`)
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

# resolve per-project policy (mirror of scripts/common.sh)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd || printf '%s' "$PROJECT_DIR")"
PROJ_DIR="$GD/projects/$(printf '%s' "$PROJECT_DIR" | sed 's#/#-#g')"
SOFT=; HARD=; SCOPE=builtin
if [ -f "$PROJ_DIR/config" ]; then . "$PROJ_DIR/config"; SCOPE=project
elif [ -f "$GD/config" ]; then . "$GD/config"; SCOPE=global; fi
: "${SOFT:=80}"; : "${HARD:=90}"

five=$(printf '%s' "$body" | jq -r '.five_hour.utilization // 0'); five=${five%.*}
state="ENABLED"; off=""
[ -f "$PROJ_DIR/off" ] && { state="DISABLED"; off="project"; }
[ -f "$GD/off" ] && { state="DISABLED"; off="${off:+$off+}global"; }

echo "Gate:  $state   soft=${SOFT}  hard=${HARD}  (policy: $SCOPE)"
echo "       project: $PROJECT_DIR"
[ "$state" = DISABLED ] && echo "       disabled via: $off kill switch"
if [ "$state" = ENABLED ]; then
  if [ "${five:-0}" -ge "$HARD" ] 2>/dev/null; then
    echo "       -> HARD BLOCKING now (5h ${five}% >= ${HARD}%)"
  elif [ "${five:-0}" -ge "$SOFT" ] 2>/dev/null; then
    echo "       -> soft nudging (5h ${five}% >= ${SOFT}%, below hard ${HARD})"
  else
    echo "       -> not gating (5h ${five}% below limits)"
  fi
fi
```

## Resolve the target scope (for every control action below)

The control actions write the **project** policy by default, or the **global** default when the
argument includes `--global`. Run this first, then the action block; it sets `$TARGET` and `$LABEL`:

```bash
GD="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/usage-gate"; mkdir -p "$GD"
if [ "$GLOBAL" = 1 ]; then            # set GLOBAL=1 when the arg has --global
  TARGET="$GD"; LABEL="global"
else
  PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
  PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd || printf '%s' "$PROJECT_DIR")"
  TARGET="$GD/projects/$(printf '%s' "$PROJECT_DIR" | sed 's#/#-#g')"
  LABEL="project ($PROJECT_DIR)"
fi
mkdir -p "$TARGET"
```

## Enable (`on`) / Disable (`off`)

Run the scope block above first. Then, for `on`:

```bash
rm -f "$TARGET/off" && echo "Usage gate ENABLED for $LABEL."
# a still-present kill switch in the OTHER scope keeps the gate disabled — warn if so:
[ -f "$GD/off" ] && [ "$GLOBAL" != 1 ] && echo "NOTE: a GLOBAL kill switch still disables the gate everywhere (clear with /usage:check on --global)."
```

For `off`:

```bash
touch "$TARGET/off" && echo "Usage gate DISABLED for $LABEL (re-enable with /usage:check on)."
```

## Set a limit (`soft N` / `hard N`)

Run the scope block first. Validate N is an integer 1–100 (or the literal `off` to clear), then
run this, substituting `KEY` with `SOFT` or `HARD` and `N` with the value. For `off`, omit the
final append line so the key is removed (that limit falls back to the global/built-in value):

```bash
F="$TARGET/config"; touch "$F"
old=$(sed -n 's/^KEY=\(.*\)/\1/p' "$F")
grep -v '^KEY=' "$F" > "$F.tmp" && mv "$F.tmp" "$F"
printf 'KEY=%s\n' "N" >> "$F"
echo "KEY limit set to N% for $LABEL (was ${old:-unset})."
```
