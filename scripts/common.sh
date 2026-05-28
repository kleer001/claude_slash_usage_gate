#!/usr/bin/env bash
# Shared paths and config for the usage gate. Sourced by gate.sh and refresh.sh.
# Runtime state lives in the user config dir (not the plugin dir, so it survives
# plugin updates and is shared with the /usage:check skill).
#
# Scope model: the 5-hour usage CACHE is account-wide, so it stays global. The gate
# POLICY (SOFT/HARD thresholds and the off kill switch) resolves PER PROJECT, falling
# back to a global default, then to built-in defaults. The project is identified by
# $1 (the hook passes $CLAUDE_PROJECT_DIR) or, when no arg is given (the skill, which
# does not receive CLAUDE_PROJECT_DIR), by $CLAUDE_PROJECT_DIR then $PWD.

GATE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/usage-gate"
CACHE="$GATE_DIR/cache"               # GLOBAL: last-known 5-hour utilization percent
WARN="$GATE_DIR/soft-warned"          # GLOBAL: rate-limits repeated soft nudges
CRED="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
GLOBAL_CONFIG="$GATE_DIR/config"      # global default policy (SOFT=/HARD=)
GLOBAL_OFF="$GATE_DIR/off"            # global kill switch

TTL=300         # seconds: refresh re-fetches the API only when cache is older than this
STALE=900       # seconds: gate ignores cache older than this and fails open
SOFT_REPEAT=60  # seconds: minimum gap between soft nudges

# --- resolve the project (arg from hook, else env, else cwd) and its state dir ---
PROJECT_DIR="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd || printf '%s' "$PROJECT_DIR")"
PROJ_KEY="$(printf '%s' "$PROJECT_DIR" | sed 's#/#-#g')"
PROJ_DIR="$GATE_DIR/projects/$PROJ_KEY"
PROJ_CONFIG="$PROJ_DIR/config"
PROJ_OFF="$PROJ_DIR/off"

mkdir -p "$GATE_DIR" 2>/dev/null

# --- resolve policy: project config overrides global default; built-in 80/90 fallback ---
SOFT=; HARD=; SCOPE=builtin
if [ -f "$PROJ_CONFIG" ]; then
  . "$PROJ_CONFIG" 2>/dev/null; SCOPE=project
elif [ -f "$GLOBAL_CONFIG" ]; then
  . "$GLOBAL_CONFIG" 2>/dev/null; SCOPE=global
fi
: "${SOFT:=80}"; : "${HARD:=90}"

# gate is disabled if EITHER the project or the global kill switch exists
gate_off() { [ -f "$PROJ_OFF" ] || [ -f "$GLOBAL_OFF" ]; }
