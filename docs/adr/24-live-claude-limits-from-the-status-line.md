# 24. Live Claude limits from the status line

- Status: Accepted
- Date: 2026-09-30

## Context
ADR 21 reads Claude's limits from `cachedUsageUtilization` in `.claude.json`. Claude Code rewrites that cache only now and then: on the owner's Mac it was 8 h and 21 h old while Claude Code ran. Stale limits make the cards and the 80 %/95 % warnings useless (owner, 2026-09-30). CodexBar gets fresh figures with the sign-in token from the Keychain and an API call, a hidden `claude` run that types `/usage`, or browser cookies. vorssaint reads the Claude desktop app's history file (ADR 20, dropped in ADR 21). Claude Code already hands its status line command `rate_limits` (`five_hour`, `seven_day`: `used_percentage`, `resets_at`) with each reply.

## Decision
- **Connect also steps in front of the profile's status line.** `statusLine.command` becomes `"<hook>" statusline <root> [<own command>]`, both base64. Other `statusLine` keys stay. With no status line of its own, the profile gets one that prints nothing.
- **The hook** keeps only the windows from the input, saves them to `Application Support/OpusBar/limits/claude-<root>.json` (an unchanged reading at most every 20 s), then runs the own command through `/bin/sh -c` with the same input and returns its output and exit status.
- **Disconnect** puts the own command back, or removes the status line OpusBar added. A profile connected before this change gets the status line at launch, only when its hooks are in and the hook copy exists; the settings file is backed up first, as for hooks.
- **Reading:** a profile's live file maps to its account (`oauthAccount.accountUuid`) and replaces the cached windows it names when it is newer; Opus and Sonnet windows stay cached. The app looks every 15 s and when the menu opens.
- **No token, no network:** ADR 4 holds. CodexBar's token call stays out.
- Codex is unchanged: its session logs carry the limits with each reply (ADR 20).

## Consequences
- Claude limits are as fresh as the last reply in any session of that profile. Use from another device shows only after the next reply here.
- A profile whose status line OpusBar wraps shows the same line as before. If OpusBar's hook copy is deleted without Disconnect, the status line goes blank until the profile's settings are fixed or OpusBar reconnects.
- `rate_limits` in the status line input is Claude Code's format; an unknown shape falls back to the cache.
