# 16. Cat coats and options are free; three coats with clear rights

- Status: Accepted (amends 10 and 13 on coats)
- Date: 2026-09-30

## Context
ADR 10 put extra coats in Pro; ADR 13 deferred them until each sheet's art rights were cleared. Checked 2026-09-30: Classic and Tora are the original X11 oneko bitmaps (drawn by Juan Gotoh, bitmaps by Masayuki Koba, oneko by Tatsuya Kato), confirmed free to use, modify and redistribute and treated as public domain by Debian, the FSF and Fedora. Catppuccin (k01e-01/catppuccineko) is MIT. Black and Calico are community art with no stated license.

## Decision
- Coats: Classic (default), Tora, Catppuccin. Black and Calico are not shipped.
- Credits and third-party notices live in the repo `LICENSE` (Third-party notices section), nowhere in the app UI. The MIT and OFL license texts stay as plain files in the app bundle because those licenses require the text with every copy (owner, 2026-09-30).
- Every cat option is free: coat, pose per state, menu bar look. Pro stays Usage and Spend (ADR 15).
- Options only choose among frames already on the sheet; the animation budget of ADR 9 still holds (menu bar at most 4 fps, stops 30 s after the last change, Reduce Motion stills).

## Consequences
- Any new coat needs its rights checked and recorded here or in a new ADR first.
- Recolors of the public-domain Classic art remain an option later, owned outright.
