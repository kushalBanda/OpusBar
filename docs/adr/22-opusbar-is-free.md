# 22. OpusBar is free: no Pro, no license

- Status: Accepted (network call amended by 23)
- Date: 2026-09-30

## Context
OpusBar is the owner's first Mac app. The goal for v1 is users and feedback, not revenue. The closest apps (CodexBar, vorssaint) are free and already show usage and cost history, so a paid Pro around Usage and Spend is a weak pitch. The owner has no Apple Developer account, so builds cannot be notarized: a paid app that opens with a Gatekeeper warning would cost trust and support time.

## Decision
- Every feature is free: all usage ranges (24 h, 7 d, 30 d, 90 d), daily bars, per-account spend, limits and notifications, all cat options.
- Removed: `Entitlements`, `LicenseProvider`, `PolarLicenseProvider`, the Keychain license cache, the License pane, the Free/Pro badge (the sidebar shows the version), lock glyphs and Unlock prompts, `UsageRange.isAvailable(isPro:)`.
- OpusBar makes no network call now. ADR 4's only exception (the Polar key check) is gone.
- Distribution without notarization is planned in M5 (Homebrew tap; a `curl` install if Homebrew restricts it).

## Consequences
- Supersedes ADRs 10, 13, 14 and 15's Pro parts, and ADR 19's gate.
- A key saved by an earlier build stays in the login Keychain (service of the old cache) until the user deletes it; nothing reads it.
- Charging later means a new ADR and new code; the removed code stays in git history (before this ADR).
