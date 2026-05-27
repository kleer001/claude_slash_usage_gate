# usage — Claude Code usage gate

A Claude Code plugin that watches your Claude.ai rate-limit usage and **gates work on the
5-hour window**: a *soft* "wrap up and save" nudge at one threshold, and a *hard* tool-call
block at a higher one. Ships a `/usage:check` skill to report usage and control the gate.

## Install

```
/plugin marketplace add kleer001/claude_slash_usage_gate
/plugin install usage@usage-gate
```

Then `/reload-plugins` (or restart Claude Code) to activate the hooks.

Local development:

```
claude --plugin-dir /path/to/claude_slash_usage_gate
```

## Commands

| Command | Action |
|---|---|
| `/usage:check` | Show 5-hour and 7-day usage (with reset countdowns) + gate status |
| `/usage:check on` / `off` | Enable / disable the gate |
| `/usage:check soft N` / `soft off` | Set / clear the soft (nudge) limit |
| `/usage:check hard N` / `hard off` | Set / clear the hard (block) limit |

Defaults: `soft 80`, `hard 90`, enabled.

## How it works

- A `PostToolUse` hook (async, non-blocking) refreshes a cached 5-hour percentage from the
  OAuth usage API at most once per 5 minutes — under the API's rate-limit window.
- A `PreToolUse` hook reads that cache before each tool call: at/above the **hard** limit it
  blocks the call (`exit 2`); at/above the **soft** limit it injects a non-blocking "wrap up
  and save" reminder; otherwise it allows. It fails **open** — missing/stale cache, no token,
  or the kill switch all allow work to proceed.

When hard-blocked, *all* tool calls are blocked (including the gate's own controls), so the
escape hatch is a plain file: `touch ~/.claude/usage-gate/off` re-enables work immediately.

State lives in `~/.claude/usage-gate/` (`config`, `cache`, `off`) — outside the plugin, so it
survives plugin updates.

## Requirements

- A Claude.ai subscription (Pro/Max) — the usage API only returns data for those accounts.
- `jq` and `curl` on `PATH`.
- The OAuth token in `~/.claude/.credentials.json` (written by Claude Code at login).

## License

MIT
