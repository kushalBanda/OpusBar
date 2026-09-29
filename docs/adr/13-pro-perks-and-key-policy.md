# 13. Pro perks for v1 and license key policy

- Status: Accepted (amends 10; store and price amended by 14)
- Date: 2026-09-29

## Context
ADR 10 listed Pro as jump to session, Usage and Spend, extra cat coats and every display. Two of those don't hold up: macOS already shows status items on every display's menu bar, and the extra coat sheets have unclear art licensing. ADR 10 also left the key policy open.

## Decision
- Pro in v1: jump to session and Usage and Spend. Price unchanged ($5, one-time, Gumroad).
- "Every display" is dropped: it would sell something macOS does for free.
- Extra coats are deferred until each sheet's art provenance is cleared; Classic stays free.
- One key unlocks any number of Macs (honor system). Verification sends `increment_uses_count=false`. Refunded, charged-back or disputed purchases are not Pro.
- Jump to session brings the session's terminal app forward (parent-process walk to a GUI app). No Apple Events, so no Automation permission prompt and no exact-tab selection.

## Consequences
- No device-reset support load; a leaked key can be refunded/revoked in Gumroad.
- The Pro pitch rests on jump + Usage and Spend until coats return.
