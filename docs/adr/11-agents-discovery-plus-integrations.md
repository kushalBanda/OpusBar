# 11. Four agents: process discovery for all, integrations for full states

- Status: Accepted (pi/OMP superseded by 18)
- Date: 2026-09-28

## Context
v1 was Claude Code only. The owner wants Claude Code, Codex, pi and OMP; OpenCode is deferred to after v1. Proven local logic exists for finding live Codex, Claude and pi/OMP sessions from the process list plus on-disk session metadata. That approach gives only live/active/idle; hooks give the rich states. Codex 0.155 ships Claude-style hooks (`~/.codex/hooks.json`, same event names, user trust step). pi keeps sessions under `~/.pi/agent/sessions`.

## Decision
- Discovery for all four agents: libproc process list, argv and cwd (never another process's environment), matched to the newest session record with the same cwd changed after process start. Only ids, cwds and timestamps are read.
- Integrations for full states through the existing bridge, with `opusbar-hook --agent <name>`: Claude Code and Codex hooks in M2; pi/OMP extension in M2b once its API is verified. OpenCode (SQLite discovery + plugin) after v1.
- Codex hook trust stays the user's action inside Codex; OpusBar never writes trust entries.
- `AgentKind` travels on the wire as an optional field; missing means Claude Code, so M1 hooks keep working.

## Consequences
- Sessions show up even before any integration is installed, or when it can't be.
- Discovery adds a 30 s bounded scan while the app runs (≤ 64 processes, ≤ 512 dir entries, 250 ms).
- Each agent's on-disk format is not a public contract; parsers must fail soft to pid-only rows.
- Extends ADR 4's data access: process list, argv, cwd, and session metadata files, all local.
