# 2. Hook bridge: tiny binary to a Unix socket, always exit 0

- Status: Accepted
- Date: 2026-09-28

## Context
Claude Code reports session activity only through hooks. Whatever runs in a hook must never slow or break Claude, including when OpusBar isn't running.

## Decision
- Claude runs `opusbar-hook` for 12 events: SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest, Notification, SubagentStart, SubagentStop, Stop, StopFailure, SessionEnd.
- The hook reads stdin (1 MB cap, rest drained), slims it (ADR 4), adds `ts` (ms at hook start), `pid` (`getppid()`, verified to be the `claude` process) and 4 terminal vars.
- It sends one JSON line `{v, ts, pid, term, e}` per connection to `~/Library/Application Support/OpusBar/events.sock` (dir 0700, socket 0600; falls back to `~/.opusbar/events.sock` past 103 bytes). Non-blocking connect with a 200 ms deadline, `SO_NOSIGPIPE`.
- It always exits 0 and never prints. No socket, refused, timeout or bad input: exit 0 silently.
- The app accepts, reads one line (64 KB cap, 500 ms receive timeout), rejects oversize or unknown `v`.
- Hook and app share path and wire code through `OpusBarWire`.

## Consequences
- Quitting OpusBar is invisible to Claude.
- The installed hook command points at a stable copy (`Application Support/OpusBar/bin/opusbar-hook`, M2) so moving the app doesn't break hooks.
- Wire changes need a version bump; old apps drop unknown `v`.
