# 3. Async hooks, ordered by hook-start timestamp

- Status: Accepted (amended by 12 for Codex)
- Date: 2026-09-28

## Context
Synchronous hooks guarantee order but add ~10–20 ms to every tool call. Async hooks (`"async": true`) never block Claude but may arrive out of order.

## Decision
- Register every hook with `"async": true, "timeout": 5, "matcher": "*"`.
- Each session keeps `lastEventTs`; the reducer ignores events older than it.
- Exception: `SessionEnd` always removes, even if late.

## Consequences
- Zero added latency for Claude.
- `ts` is hook start, not emit time: two events a few ms apart can still invert, giving a brief wrong state the next event corrects.
- Fallback if this bites: make only `Stop`, `StopFailure`, `SessionEnd` synchronous.
