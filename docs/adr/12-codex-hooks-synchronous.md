# 12. Codex hooks run synchronously

- Status: Accepted (amends 3 for Codex)
- Date: 2026-09-28

## Context
ADR 3 made every hook async. Codex 0.155 accepts the same entry keys (`command`, `timeout`, `async`, `statusMessage`) and fires Claude-style events. In a real `codex exec` run with async entries, SessionStart and UserPromptSubmit arrived but Stop never did: Codex exits before a pending async hook runs. With synchronous entries every event arrived (SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Stop).

## Decision
- Codex entries omit `async` (synchronous), `timeout: 5`, `matcher: "*"`, command `"<support>/bin/opusbar-hook" --agent codex`, in `$CODEX_HOME/hooks.json` or `~/.codex/hooks.json`.
- Events: SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PermissionRequest, SubagentStart, SubagentStop, Stop, SessionEnd (Codex has no Notification or StopFailure).
- Codex's hook trust stays the user's step (approve in Codex `/hooks`); OpusBar never writes `trusted_hash`.
- Claude Code stays async (ADR 3).

## Consequences
- Each Codex event waits for the hook: a few ms with OpusBar running, at most the 200 ms connect deadline when it isn't.
- Codex events arrive in order, so the timestamp guard rarely matters there.
- The command string is stable across reinstalls, so a trust approval survives reconnecting.
