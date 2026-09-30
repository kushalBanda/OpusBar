# 19. Usage and Spend from the agents' local logs

- Status: Accepted
- Date: 2026-09-30

## Context
M4 (Usage and Spend, owner-approved 2026-09-30) needs tokens and cost for Claude Code and Codex. ADR 4 asks that any new data access be scoped explicitly. The design follows vorssaint-utils `Services/AgentUsage` (studied, own code); CodexBar's cost scanner was compared.

## Decision
- **Read, locally, in place:** Claude Code `<config root>/projects/**/*.jsonl` for every known profile root (incl. `<session>/subagents/`), and Codex `$CODEX_HOME` or `~/.codex` `sessions/**` + `archived_sessions/**`. Nothing is copied, cached on disk or sent. No price download, no `codex app-server`, no `~/.claude.json`, no Claude desktop plan-usage file.
- **Kept per reply:** agent, time, model, project folder, session id, token counts (input, cache write incl. 1 h part, cache read, output), fast tier, US-only inference, web search count. Prompt, reply and tool text are never decoded into anything kept. A byte prefilter skips non-usage lines before JSON parsing.
- **Duplicates:** a reply is keyed by Claude message id + request id (or session + message id), Codex response id (or session + running total). Copies merge by the largest value per field, so streamed blocks, the same reply in two files and re-reads never double count.
- **Codex:** usage from `token_usage_record`; older rollouts fall back to `token_count` totals. Codex input includes cached and cache-write tokens; they are split into disjoint counts.
- **Cost = "API value":** tokens at API list prices from `usage-prices.json` shipped in the app (Claude and OpenAI pages, reviewed date in the file). Longest family match at a word break; an unlisted sibling (mini, nano, …) or unknown model gets no price and is counted as unpriced, never guessed.
- **Projects:** the git repository folder that holds the reply's cwd, else the folder's name.
- **Reading:** per-file cursor (offset, inode, unfinished line); files changed within 90 days are read at launch in parallel (one worker per file, replies merged in file order), then FSEvents file events read only appended bytes; a dropdown open refreshes. Records older than 90 days are dropped from memory.
- **Gate:** the last 24 hours is free; 7/30/90 days and the daily chart are Pro, through `UsageRange.isAvailable(isPro:)` only.

## Consequences
- The strip and pane show nothing until the first read finishes (about 2 s for ~1 GB of logs on an 8-core Mac, optimized build).
- Prices go stale between releases; a new model reads "unpriced" until the list is updated in a release.
- Memory holds one small record per reply for 90 days (about 43k records here).
- Undocumented log formats can change; readers skip what they don't recognise rather than fail.
