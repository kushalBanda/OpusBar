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

## Sandbox
- Organization "OpusBar" (slug `opusbar`), id `c30a3772-fd5a-4ab6-b9be-0245de4a1350`. Not a secret.
- Debug run: `open build/OpusBar.app --args --settings license --polar-sandbox c30a3772-fd5a-4ab6-b9be-0245de4a1350`.
- Checked live 2026-09-29: validate with no token answers 404 `ResourceNotFound` for an unknown key.
- Access tokens never go in the app or the repo.
- Created by API 2026-09-29: benefit "OpusBar Pro license key" `8ec80902-f058-4197-ab7d-d0708ad2c51a` (license_keys, prefix OPUSBAR, no expiry, no activation or usage limit); product "OpusBar Pro" `5e4cc1fa-fba5-48d7-8613-ba5a090da4ff`, one-time $6.99, carrying that benefit; checkout link https://sandbox-api.polar.sh/v1/checkout-links/polar_cl_lhhOin1IJlKBJzHlBzAUOHhcvS9x7C5D6FbBP0CjZic/redirect (debug `--polar-sandbox` Buy button uses it). Test card 4242 4242 4242 4242.
- Live setup mirrors this; then fill `PolarStore.live` (organization id, checkout link).
