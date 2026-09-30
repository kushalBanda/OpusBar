# 17. Twenty-one coats: the clear 17 plus four recolours of our own

- Status: Accepted (amends 16)
- Date: 2026-09-30

## Context
The owner wanted all 24 coats of 0xdhrv/oneko. Checked 2026-09-30 per its docs/skins.md and upstreams:
- Classic, Tora: public-domain X11 oneko art (ADR 16).
- Catppuccin: k01e-01/catppuccineko, MIT.
- Maia, Vaporwave: kyrie25/spicetify-oneko, MIT.
- Ginger, Sage, Siamese, Strawberry Milk, Blue Frost, Lavender, Tuxedo, Peach, Honey, Mocha, Mint, Midnight Blue: generated from Classic by 0xdhrv/oneko, MIT.
- Black, Gray, Calico, Ghost, Silver, Spirit, Valentine: tallypaws/oneko_db, which has no license (all rights reserved).

## Decision
- Ship the 17 with clear rights, unmodified.
- Black, Gray, Silver and Ghost are recreated by OpusBar as recolours of the Classic sheet (`scripts/make-recolors.swift`: swap its white fill and black outline). They are ours; the oneko_db sheets are not used.
- Calico, Spirit and Valentine are not shipped.
- Sheets live in `Resources/Coats/`; MIT texts (catppuccineko, spicetify-oneko, 0xdhrv/oneko) travel in the bundle; credits in the repo LICENSE only.
- A test fails if any file in `Coats/` isn't a shipped coat, or any pose frame of a sheet is empty.

## Consequences
- 21 coats, all free (ADR 16).
- New coats still need their rights recorded first.
