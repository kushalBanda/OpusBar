# 25. Automatic updates and a what's-new card

- Status: Accepted
- Date: 2026-10-04

## Context
ADR 23 installs an update only on a click, so most users stay on old builds until they open Settings. The owner wants updates to arrive on their own and to show, simply and once, what changed (owner, 2026-10-03). The update check, the Ed25519 signature and the checks on the unpacked app stay as ADR 23 set them.

## Decision
- **Setting:** "Install updates automatically", on by default, in Settings › About under "Check for updates automatically" and off while that one is off.
- **Staging:** when the daily check finds a newer release and the setting is on, the app downloads the zip and signature, verifies them, unpacks the app and checks its bundle id and version, all without touching the running app. The release is then "ready". A failed step is silent: the release stays on offer for a click.
- **Swap on quit:** when OpusBar quits (`applicationWillTerminate`) with a ready release, the same helper script as the click path waits for the process to exit, moves the new app in and does not reopen it; the next launch is the new version. "Relaunch Now" in Settings does the same and reopens at once. If the swap fails, the old app is put back.
- **Preflight:** the folder must be writable and the app must not run from a translocated copy; checked before downloading.
- **What's new:** just before a swap, the app stores the new version and up to four bullet lines taken from the release body (`ReleaseNotes.highlights`; `release.sh` fills the body from the `## <version>` section of `CHANGELOG.md`). On the first launch of that version the Sessions tab shows a green card with the cat, "Updated to <version>" and those lines; "Got it" clears it, "Full notes" opens the release page. A note for another version is dropped at launch. With no bullets the card says "Fixes and improvements."
- **Changelog is the source:** every release needs a `## <version>` section in `CHANGELOG.md` before `release.sh --publish`, with one plain line per change.
- **Motion:** the lines settle in one after another; with Reduce Motion they appear at once.
- Amends ADR 23: an update no longer waits for a click when the setting is on. No new network call; the download is the same release asset.

## Consequences
- Users on a build older than 0.1.2 take one manual update; later ones install themselves.
- An update is applied only when the user quits or relaunches, so a running session view is never cut off.
- Staged downloads live in the temporary folder; if the system clears it before the user quits, the next daily check downloads again.
- Release notes are read from GitHub's release body, so they can be edited after publishing and the card follows.
