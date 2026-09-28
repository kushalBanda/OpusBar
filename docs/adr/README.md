# Architecture decision records

One decision per file: context, decision, consequences. Never rewrite an accepted ADR; add a new one that supersedes it and update the old one's status.

| # | Decision | Status |
|---|---|---|
| [1](1-swiftpm-with-xcode-toolchain.md) | SwiftPM package, Xcode 15.4 via DEVELOPER_DIR | Accepted |
| [2](2-hook-bridge-over-unix-socket.md) | Hook bridge: tiny binary to a Unix socket, always exit 0 | Accepted |
| [3](3-async-hooks-with-timestamp-ordering.md) | Async hooks, ordered by hook-start timestamp | Accepted |
| [4](4-local-only-slim-events.md) | Local only: whitelist slimming, no telemetry | Accepted |
| [5](5-status-item-popover-and-settings-window.md) | NSStatusItem + transient NSPopover; AppKit Settings window | Accepted |
| [6](6-pure-reducer-session-state.md) | Pure reducer and pruner behind an observable store | Accepted |
| [7](7-claude-config-root-resolution.md) | Claude config root: literal CLAUDE_CONFIG_DIR, else ~/.claude | Accepted |
| [8](8-git-branch-from-head-file.md) | Git branch read from .git/HEAD | Accepted |
| [9](9-oneko-mascot-and-animation-budget.md) | oneko mascot, 4 fps menu bar cap, 30 s stop | Accepted |
| [10](10-one-time-pro-unlock.md) | One-time $5 Pro unlock behind Entitlements | Accepted (M3) |

Template:

```markdown
# N. Title

- Status: Proposed | Accepted | Superseded by N
- Date: YYYY-MM-DD

## Context
## Decision
## Consequences
```
