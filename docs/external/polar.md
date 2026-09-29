# Polar (store for OpusBar Pro)

ADR 14. Dashboard: https://polar.sh (owner's account).

## Setup the owner does
- Product "OpusBar Pro", one-time, $6.99.
- Benefit: License key. No activation limit, no usage limit, no expiry. Prefix optional (for example `OPUSBAR`).
- Organization id (Settings > General) goes into the app as a build constant. It is not a secret.
- Checkout link for the product goes into the app's Buy button.

## Giveaway keys
- Option A: Discounts > new, 100% off, a code (for example `FRIENDS`), maximum redemptions set, limited to OpusBar Pro. The recipient checks out with the code and gets a real key by email.
- Option B: a second, hidden product "OpusBar Pro (gift)" at $0 with the same license key benefit. Share its checkout link; free products never ask for a card. Anyone with the link can claim, so share it privately or archive it after.
- A key can be revoked from the benefit's grants list; the app treats revoked as not Pro.

## Payouts
Stripe Connect Express, India supported. Fees: $2 per month with payouts, 0.25% + $0.25 per payout, 0.25–1% currency conversion. Withdraw monthly or less often.
