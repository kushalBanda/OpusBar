# 7. Claude config root: literal CLAUDE_CONFIG_DIR, else ~/.claude

- Status: Accepted
- Date: 2026-09-28

## Context
Claude Code reads settings and writes transcripts under a config root chosen by `CLAUDE_CONFIG_DIR`. Hardcoding `~/.claude/settings.json` breaks for users who set it, and one user can run sessions under several roots at once (observed: `~/.claude` and `~/.claude-kb48` side by side).

## Decision
`ClaudeConfigPaths` (OpusBarCore) resolves the root the way Claude does:
- Non-empty `CLAUDE_CONFIG_DIR` is one literal directory. A leading `/` is absolute; anything else resolves against the working directory; `~` is not expanded.
- Empty or unset means `$HOME/.claude` (falling back to the user's home directory when `HOME` is empty).
- `settingsURL` = root/`settings.json` (installer, M2). `projectsRoot` = root/`projects` (usage, M4).
- `OpusBarPaths` holds only OpusBar's own files.

## Consequences
- The hook installer targets a root, not a fixed file, and must handle more than one.
- A Finder-launched app doesn't inherit shell variables, so its own environment alone can miss a custom root. Discovering roots (login shell, running `claude` processes) is an open M2 decision.
