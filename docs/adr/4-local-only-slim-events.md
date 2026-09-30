# 4. Local only: whitelist slimming, no telemetry

- Status: Accepted
- Date: 2026-09-28

## Context
Hook payloads contain prompts, tool inputs, tool responses and assistant messages. The product promise is local-only with no telemetry.

## Decision
- The hook keeps only: `session_id`, `hook_event_name`, `cwd`, `transcript_path`, `permission_mode`, `tool_name`, `notification_type`, `source`, `reason`, `agent_id`, `agent_type`. Everything else is dropped inside the hook process.
- Only `TERM_PROGRAM`, `TERM_SESSION_ID`, `ITERM_SESSION_ID`, `TMUX` are read from the environment; never the full environment.
- Session state lives in memory. Nothing is sent off the machine.
- The only network call in the product is the optional license key check with Polar (M3, ADRs 10, 14).
- Any new data access (other files, other processes, network) needs the owner's sign-off first.

## Consequences
- Prompt text never reaches the app, the socket or disk.
- Features that need more (e.g. usage from transcripts, M4) read local files only and must be scoped explicitly. Usage and Spend is scoped in ADR 19.
