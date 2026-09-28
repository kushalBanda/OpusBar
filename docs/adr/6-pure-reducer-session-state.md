# 6. Session state: pure reducer and pruner behind an observable store

- Status: Accepted
- Date: 2026-09-28

## Context
Session logic must be testable without AppKit, timers or sockets.

## Decision
- `SessionReducer.reduce(state, event, now)` is pure. States: idle, thinking, working, needsAttention, done, error. Unknown sessions are created on first event.
- `SessionPruner.prune(state, now, finishedTTL, isAlive)` is pure: removes done/error after the TTL (default 600 s) and sessions whose pid is dead (`kill(pid, 0) == 0 || errno == EPERM` means alive).
- `SessionStore` (`@MainActor @Observable`) wraps both, reads the git branch (ADR 8), and runs a 30 s prune timer only while sessions exist.
- Aggregate for the menu bar: error > needsAttention > working > thinking > done > idle, plus needs-you and active counts.
- No hook fires when the user answers a permission prompt; needsAttention clears on the next tool, prompt or stop event.

## Consequences
- The whole FSM is covered by fast unit tests.
- An idle app does no periodic work.
- A row can stay yellow after a denied prompt until Claude's next event.
