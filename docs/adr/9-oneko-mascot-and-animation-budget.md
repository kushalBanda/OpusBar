# 9. oneko pixel cat mascot, with a strict animation budget

- Status: Accepted
- Date: 2026-09-28

## Context
The owner chose the oneko cat (oneko.js layout: 256×128 sheet, 8×4 grid of 32 px frames). Menu bar redraws are the main idle-CPU risk: ~9 fps cost 2–4% CPU, from WindowServer redraws rather than our drawing.

## Decision
- Poses: idle sits (3,3); working runs (3,0)(3,1); thinking grooms (5,0)(6,0)(7,0)(6,0); needs you alert (7,3); done naps (2,0)(2,1); error slumps (3,2).
- Menu bar: 16 pt full-color (the 32 px frame 1:1 on Retina), nearest-neighbor, badge for needs-you count / done / error, dimmed with no sessions.
- Menu bar frames capped at 4 fps (`minFrameInterval = 0.25`); animation stops 30 s after the last session change; Reduce Motion shows still frames.
- Dropdown tiles animate at full speed only while visible.
- `oneko-classic.png` bundled with `CREDITS.md`.

## Consequences
- Measured: release 1.2–1.4% CPU while animating, 0.0% once still, ~30–40 MB RSS.
- Sprite-art licensing is separate from oneko's MIT code; each coat's provenance must be re-checked before the M5 release.
