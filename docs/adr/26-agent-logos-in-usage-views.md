# 26. Claude Code and Codex logos in usage views

- Status: Accepted
- Date: 2026-10-04

## Context
Usage limits, the API value legend and the agent rows in Settings told Claude Code and Codex apart with a small coloured dot (ADR 19, 20). The owner asked for each agent's logo instead (2026-10-03). The same logos appear on the website's "Supports Claude Code and Codex" badge and Plan limits section.

## Decision
- **Logos:** `AgentLogo` draws the agent's mark from a bundled PNG (`Resources/AgentLogos/claude.png`, `codex.png`, 96 px) as a template image tinted with `Theme.agent`, so it follows light and dark mode and keeps the validated, colour-blind-safe pair of ADR 19. If the image is missing the old dot is drawn.
- **Source:** the artwork comes from the `@lobehub/icons-static-svg` package (MIT). The marks are trademarks of Anthropic and OpenAI, used only to name each tool OpusBar works with; the README says OpusBar is not affiliated with either.
- **Where:** the limits cards and the API value legend in the menu, and the usage rows in Settings. Charts and bars keep their colours.
- **Packaging:** `Package.swift` and `scripts/bundle.sh` copy `AgentLogos`.

## Consequences
- A new agent needs a logo PNG as well as a colour.
- If either company asks, the logos can be replaced by the dots without other changes.
