# 18. pi and OMP removed: Claude Code and Codex only

- Status: Accepted (supersedes the pi/OMP part of 11)
- Date: 2026-09-30

## Context
ADR 11 added pi and OMP next to Claude Code and Codex (process discovery, session-file matching, an `opusbar.ts` extension installer, a Settings folder list). While planning M4 (Usage and Spend) the owner narrowed the product to Claude Code and Codex, the two agents the reference apps (vorssaint-utils, CodexBar) and our users center on. pi/OMP success paths were never live-verified (owner's pi key returned 401; OMP not installed).

## Decision
- `AgentKind` is `claude` and `codex` only.
- Deleted: `PiExtensionInstaller` and its generated `opusbar.ts`, `HookTarget.piFamily`, pi/OMP process classification, pi/OMP session-record reading and roots, `PiFamilyFolders` preference, Agents pane pi/OMP sections and folder tile, the reducer's `reason: aborted` rule.
- The hook drops any event whose `--agent` names an agent OpusBar doesn't know, so a leftover `opusbar.ts` from an older build can never show up as a Claude session.
- M4 reads Claude Code and Codex usage only.

## Consequences
- Anyone who connected pi/OMP with an older build keeps an inert `extensions/opusbar.ts` (its events are dropped); deleting it by hand is safe.
- Old `piSessionFolders` / `ompSessionFolders` UserDefaults keys are ignored.
- Adding an agent later means a new `AgentKind` case plus its discovery, hooks and usage reader.
