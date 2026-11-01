# 27. A notice click opens the session's app, tab or window

- Status: Accepted (amends 4 and 15)
- Date: 2026-10-31

## Context
ADR 15 removed jump to session: bringing the app forward only did what Cmd-Tab does, and an exact tab needs Automation or Accessibility. It left the door open for "a precise jump … with its permission cost stated up front". Owners run Claude Code and Codex in many hosts (Orca, Terminal, tmux, VS Code forks, desktop apps), and a click on a notice that only opens the menu sends them hunting. Plan: `docs/plans/notification-focus-session/`.

## Decision
- **Where:** a click on a session notice, and the "Show in" button on a session card, run one focus path. The notice body names the host app ("Claude Code · Orca · myproject").
- **How far, per host (each one checked on a real Mac):**
  - Orca: exact tab with `orca terminal switch`, from the `ORCA_TERMINAL_HANDLE` the hook now sends; else a match from `orca terminal list --json`. No permission.
  - tmux: `tmux switch-client` selects the pane in the client that shows it, then the client's app is focused. No permission.
  - Terminal: exact tab by tty through AppleScript. Needs Automation for Terminal.
  - iTerm2: exact pane with `iterm2:reveal?sessionid=` from `ITERM_SESSION_ID`, no permission; else by tty through AppleScript.
  - Ghostty 1.4 or later: exact split by tty through AppleScript, else the one terminal in the session's folder. Needs Automation for Ghostty. Apps built on Ghostty that set `TERM_PROGRAM=ghostty` (cmux) are not taken for it.
  - Any app: the window whose title names the session's folder or name, through Accessibility. No match raises nothing.
  - VS Code family: the title raise, then opening the repository root, which fronts the window that has it. No permission. Window only: an editor gives no way to pick its terminal tab from outside.
  - Always last: bring the app forward. No permission. A session with no app opens the menu.
- **Permissions:** asked only when a click needs one, never at launch. Accessibility is asked at most once per launch. A no never blocks: the click falls to the next level. Settings › Notifications shows each level and its state.
- **Signing:** `scripts/bundle.sh` signs with the designated requirement `identifier "dev.opusbar.OpusBar"`, so grants survive updates. An ad-hoc signature otherwise ties them to each build's hash.
- **Hook variables (amends ADR 4):** the hook also reads `ORCA_TERMINAL_HANDLE`, five names in all. Still never the full environment. Each value is checked for shape before it reaches a command line.
- **Helper apps:** Orca runs its terminals in a helper app under Application Support, a child of launchd. A helper app there stands for the installed app with the same bundle id.
- **Code:** pure planning and fallback in `OpusBarCore/Focus` (tested), AppKit side in `OpusBar/Focus/FocusRunner.swift`. A new host is a `KnownHost` case plus its steps.

## Consequences
- The pinned requirement means any app ad-hoc signed with the bundle id `dev.opusbar.OpusBar` meets it and inherits the Automation and Accessibility grants. A Developer ID signature would remove this; ADR 23 keeps the app unsigned for now.
- The first update after this change asks for permissions once more.
- Only hosts checked on a real Mac have an exact route. WezTerm, kitty, cmux, the Codex app and the Claude Code extension panel get the window raise and the app; a route for each is added once it can be tested.
- Each release runs the host checklist in `docs/plans/notification-focus-session/05-host-matrix.md`.
