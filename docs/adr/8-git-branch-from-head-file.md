# 8. Git branch read from .git/HEAD, never by running git

- Status: Accepted
- Date: 2026-09-28

## Context
Cards show the session's branch. Spawning `git` per event costs CPU and depends on PATH.

## Decision
- `GitBranchReader.branch(atPath:)` walks up from the cwd to `.git`. A directory is used directly; a `.git` file (worktree) is followed via `gitdir:` (absolute or relative). The walk stops at `/`.
- `ref: refs/heads/x` gives `x`; a detached HEAD gives the first 7 characters of the sha.
- The store re-reads the branch on a new session, a cwd change, SessionStart, UserPromptSubmit and Stop only.

## Consequences
- A few small file reads per turn; no subprocesses.
- Exotic setups (`GIT_DIR` overrides, packed symbolic refs) may show no branch. Acceptable for a label.
