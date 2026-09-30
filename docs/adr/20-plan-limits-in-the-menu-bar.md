# 20. Plan limits and usage in the menu bar

- Status: Accepted (menu bar reading removed 2026-09-30, owner: limits show in the dropdown's Usage tab only; Claude source superseded by 21)
- Date: 2026-09-30

## Context
The owner asked for vorssaint-utils' rate limit reading in OpusBar's menu bar, with usage beside it, done "the same" as vorssaint (2026-09-30). vorssaint reads limits from local files only and shows, on its resting notch wing, the allowance closest to running out as a ring and a percentage, or today's API value when no allowance is known. CodexBar's Claude source (Keychain OAuth token plus a call to Anthropic's usage endpoint) was compared and not taken: it breaks ADR 4. This amends ADR 19, which excluded `~/.claude.json` and the Claude desktop app's file.

## Decision
- **Codex:** the `rate_limits` object on `token_count` lines of the rollouts OpusBar already reads. Only the main allowance (`limit_id` "codex" or none); windows are told apart by length (5 h session, week, other). The newest reading across rollouts wins.
- **Claude:** `~/Library/Application Support/Claude/plan-usage-history.json`, which the Claude desktop app writes while its menu bar icon is on (versions 1 and 2; keys fh, sd, so, sn). Reset times are estimated as vorssaint does: a session renews 5 h after the UTC hour its use began (narrowed by Claude Code's first reply), a week 7 days after the last drop. A stale or unknown file shows nothing.
- **Account check:** `oauthAccount.organizationUuid` from `~/.claude.json`, so another account's readings are ignored. Nothing else in that file is kept.
- **Menu bar:** beside the cat, the tightest window as "N%" (left by default, or used), in orange from 80 % spent and red from 95 % (the ring was tried and removed, owner 2026-09-30: it didn't read clearly); with no limit, the last 24 hours' API value; the tooltip lists every window with its reset. Settings > Cat > Menu bar: "Beside the cat" (Plan limit / Nothing) and "Show the limit as" (Left / Used). Free.
- Files are read again only when their modification date changes; the worker also looks each minute, since windows renew and the app saves without a log changing.

## Consequences
- Claude limits need the Claude desktop app with its menu bar icon on; without it, only Codex limits (or the API value) show.
- Claude reset times are estimates; Codex reset times come from the server.
- A new Codex rollout format or Claude app file version shows nothing until the reader learns it.
