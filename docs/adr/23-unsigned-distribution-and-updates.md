# 23. Unsigned distribution and a signed update check

- Status: Accepted (updates amended by 25)
- Date: 2026-09-30

## Context
OpusBar is free (ADR 22) and the owner has no Apple Developer account, so builds are ad hoc signed and not notarized. Gatekeeper blocks a quarantined download once (System Settings > Privacy & Security > Open Anyway). Homebrew 5.0 disables casks in Homebrew/homebrew-cask that fail Gatekeeper from September 2026 and deprecated `--no-quarantine`; own taps are not named. A risk check (2026-09-30) found that a quarantined copy of `opusbar-hook` is killed when an agent runs it (exit 137), and approving the app doesn't clear the copy. Files fetched by `curl` or by the app's own URLSession carry no quarantine mark (checked on this Mac).

## Decision
- **Release:** `scripts/release.sh <version>` builds a universal app (arm64 + x86_64), ad hoc signed, then `dist/`: `OpusBar-<v>.zip`, its Ed25519 signature `.zip.sig`, an unversioned `OpusBar.zip`, `OpusBar-<v>.dmg`, `checksums.txt`, `install.sh`. `--publish` creates the GitHub release after a confirmation.
- **Install:** `curl -fsSL …/scripts/install.sh | bash` (checksum checked, no Gatekeeper prompt) first, the DMG as the fallback (Open Anyway once). No Homebrew (owner, 2026-09-30): the official cask repo is closed to unsigned apps, and a tap has the DMG's prompt and a second version manager next to the in-app updater. A tap can be added later if users ask.
- **Hook:** the installer removes the quarantine mark from its own hook copy, and the app refreshes that copy at launch when it exists, so an update reaches the agents.
- **Updates:** the app asks `api.github.com/repos/kushalBanda/OpusBar/releases/latest` a minute after launch and daily, only while "Check for updates automatically" is on (default on), and on Check Now. The request carries the User-Agent `OpusBar/<version>` and nothing else. An update installs only on a click: download zip and signature, verify Ed25519 against the key built into the app (`UpdateFeed.publicKey`), check bundle id and version, swap the app and relaunch; any failure changes nothing.
- **Key:** `scripts/update-key.swift` made the key once; the private key lives at `~/.config/opusbar/update-signing.key` (mode 600), never in the repo. Losing it means a new public key that installed copies won't trust.
- **No self-signed certificate:** nothing in OpusBar depends on a stable code signature any more (the license Keychain item is gone, no TCC permissions), so it would add setup for no gain.
- Amends ADR 4 and 22: the update check is the one network call.

## Consequences
- DMG downloads from the browser still need Open Anyway once; the curl install and in-app updates don't.
- Releases need a public place to download from: the repository is private today, so it must be made public (or a public releases repo used) before the first release.
- With a Developer ID later, signing and notarization slot into `release.sh`; the update signature stays.
