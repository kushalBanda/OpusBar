# 21. Claude plan limits per account, from Claude Code's cache

- Status: Accepted
- Date: 2026-09-30

## Context
The owner runs two Claude accounts (`CLAUDE_CONFIG_DIR=~/.claude` and `~/.claude-kb48`) and asked for every Claude account's limits beside Codex's, with the usage charts vorssaint shows (2026-09-30). ADR 20 read Claude's limits from the Claude desktop app's `plan-usage-history.json`: one account at a time, only while the app's menu bar icon is on, reset times estimated. It was not on the owner's Mac, so no Claude limits showed. Claude Code itself caches each account's limits in the profile's `.claude.json` (`cachedUsageUtilization`: `fetchedAtMs`, `accountUuid`, and per window `utilization` in percent and `resets_at`) whenever it checks the account. CodexBar's OAuth call stays out (ADR 4).

## Decision
- **Claude source:** `cachedUsageUtilization` in every known profile's `.claude.json` (inside a `CLAUDE_CONFIG_DIR` folder; `~/.claude.json` too for `~/.claude`). Windows read: `five_hour` (5 h), `seven_day` (week), `seven_day_opus`, `seven_day_sonnet`; other keys (codenames, extra usage) are ignored. Kept: the window figures, `accountUuid`, the fetch time, and `oauthAccount.emailAddress` for the label, only when the sign-in is the cache's account. Nothing is sent.
- **One reading per account:** profiles that share an account keep the newest reading. A reading's age shows on its card after 10 minutes; a window whose reset time passed reads as renewed.
- **Profiles found automatically:** `~/.claude-<name>` folders that hold `.claude.json` join `~/.claude`, `~/.config/claude`, `CLAUDE_CONFIG_DIR` and user-added folders (origin `detected`). They also get a Connect tile in Agents, and their logs count in usage.
- **The desktop app file is no longer read** (supersedes ADR 20's Claude source). Codex stays as ADR 20 has it.
- **Dropdown Usage tab (vorssaint's layout):** a card per account (agent dot, the name before the @ when an agent has several accounts, "updated … ago"), with the session and the longer window that binds first: % left, countdown to reset, a meter with an even-pace tick; then the range picker, the API value with tokens and replies over a trend stacked by agent (hourly for 24 h, daily otherwise; hover shows a bar's figures; legend when two agents have use), then top-3 Models and Projects with bars in the agent's color. Agent colors: Claude #D97757 / #CC6D4F (dark), Codex #5B7FFF / #6F8CF5 (dark), passed the dataviz palette checks.

- **Codex homes (owner, 2026-09-30):** `~/.codex`, `$CODEX_HOME`, `~/.codex-<name>` folders holding `sessions/` or `config.toml` (origin `detected`), and folders added with "Add Codex Folder…". Each home is one account: its own Connect tile, limits card (named by folder, e.g. "codex-work"), reset switch and spend. `auth.json` is never read, so a Codex account has no email.
- **Spend per account:** each reply carries the folder of the account that made it (`UsageRecord.account`). "By account" (Settings > Usage, dropdown "Accounts") appears when an agent has more than one account in the range; Claude accounts are named by their email, others by folder. Agents tiles show each Claude profile's email.

## Consequences
- A Claude account shows limits once Claude Code has checked it at least once in that profile; readings age between runs.
- `.claude.json` is Claude Code's private format; an unknown shape shows nothing rather than a guess.
- The account email is read and shown on this Mac only.
