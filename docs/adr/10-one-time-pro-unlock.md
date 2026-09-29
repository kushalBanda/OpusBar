# 10. One-time $5 Pro unlock behind a single Entitlements seam

- Status: Accepted (implementation in M3; perks and key policy amended by 13 and 14)
- Date: 2026-09-28

## Context
The product is free with a one-time Pro upgrade. The free/Pro line and licensing must be easy to audit and change.

## Decision
- Price: $5, one-time, sold on Gumroad.
- Free: sessions, states, menu bar cat, dropdown, notifications, launch at login, classic coat.
- Pro: jump to session, Usage and Spend, extra cat coats, every display.
- Features ask only `Entitlements.isPro`. Verification goes through a `LicenseProvider` protocol (Gumroad first), cached in the Keychain; offline stays Pro for 30 days after the last successful check.
- The license check is the product's only network call (ADR 4).
- Any change to this boundary, pricing or licensing needs the owner's sign-off.

## Consequences
- Switching stores means a new `LicenseProvider`, nothing else.
- Free users see an inline Pro hint where a Pro feature would be.
