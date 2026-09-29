# 14. Polar as the store, $6.99 one-time

- Status: Accepted (amends 10 and 13)
- Date: 2026-09-29

## Context
ADRs 10 and 13 named Gumroad at $5. The owner sells from India, so the store must pay out to an Indian bank and act as merchant of record (sales tax and VAT). At $5 the fixed per-sale fee takes about 17%.

## Decision
- Store: Polar (merchant of record). Payouts reach India through Stripe Connect Express.
- Price: $6.99, one-time. The app shows the price from one constant.
- Key check: `POST https://api.polar.sh/v1/customer-portal/license-keys/validate` with `key` and `organization_id`. No access token, so no secret ships in the app. No activation limit on the license key benefit (unlimited Macs, ADR 13); the app never calls `activate`.
- A key counts as Pro only when Polar returns `status: granted`. Revoked or disabled keys (refunds) are not Pro.
- The key is checked once, when entered, then kept in the login Keychain; Pro works offline for good with no re-check (owner, 2026-09-29). A refunded buyer who already activated keeps Pro. Deactivate forgets the key on this Mac.
- Giveaway keys: a 100% discount code with a redemption limit, or a hidden free product carrying the same license key benefit. Either way the recipient gets a real Polar key; the app needs no special path.
- The organization id is a build constant, not a secret.

## Consequences
- `PolarLicenseProvider` replaces `GumroadLicenseProvider`; nothing else in the Entitlements design changes.
- Fees on Polar's free plan: 5% + $0.50, +1.5% for international cards, plus payout costs. About $5.63 kept per $6.99 sale before payout costs.
