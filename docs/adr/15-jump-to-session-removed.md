# 15. Jump to session removed; Pro v1 is Usage and Spend

- Status: Accepted (amends 13)
- Date: 2026-09-29

## Context
M3.3 built jump to session as ADR 13 set it: bring the session's app forward, no Apple Events, no exact tab. In use it only did what Cmd-Tab does. Landing on the exact tab or window needs Automation or Accessibility permission, which doesn't fit a small, private menu bar app.

## Decision
- Jump to session is removed, for Free and Pro. No "Open <app>" button, no fallback-terminal setting, no Pro hint on cards.
- Cards keep showing where a session runs ("Terax · ttys013"), which needs no action.
- Pro in v1 is Usage and Spend (M4). Price stays $6.99 (ADR 14).
- Pro is not sold until Usage and Spend ships.

## Consequences
- Free covers everything that exists today; the License pane pitches Usage and Spend only.
- A precise jump can come back later as its own decision, with its permission cost stated up front.
