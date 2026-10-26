# Changelog

## 0.1.18

- Usage prices Claude Haiku 5.5 replies, including its higher rates for prompts over 100,000 tokens. They used to show as replies without a known price.
- Every price in the list was checked against Anthropic's and OpenAI's pricing pages. Claude Sonnet 5.5 cache reads now cost $0.10 per million tokens, not $0.20. GPT-6.1 Sol replies in fast mode cost twice the standard rate, and GPT-5.5 Cyber now has a price.

## 0.1.17

- Notifications use the standard macOS layout: app icon on the left, title and message beside it, time at the top right. The cat thumbnail on the right is gone, so the text no longer sits out of line.

## 0.1.16

- Settings › Usage is laid out again: figure tiles on one grid, the trend beside the token mix, a card per agent, then models, projects and accounts. Every row lines up edge to edge.
- Pick Overview, Claude Code or Codex at the top of Settings › Usage to see one agent's figures; its tiles break tokens into input, output, cache read and cache write.
- Plan limits in the Usage tab sit side by side, one row per account, with when each renews. A limit your pace would spend before it renews says when it runs out.
- Accounts in the Usage tab lead with their Claude or Codex logo, and lists show dollars wherever a price is known.
- Session cards show what matters at a glance: the project, what it is doing and for how long, and what it has cost, with the agent as a badge on the cat. Tap a card for its folder, terminal, tokens and billing, and to open its folder, copy its path or bring its terminal forward.
- Section headers in the Sessions tab are lighter, each with a dot in its cards' color.

## 0.1.15

- The plan limit cards at the top of the Usage tab carry the same badged Claude or Codex logo as the session cards.
- Subscription, API billing and custom endpoint badges are plain symbols again, without the grey tile; only Amazon Bedrock, Google Vertex AI and Microsoft Foundry are in color.

## 0.1.14

- Accounts in the Usage tab and in Settings › Usage say how each pays: "you@example.com · Subscription", "work · Bedrock". A profile on Bedrock, Vertex AI, Foundry or a custom endpoint goes by its folder, not the old claude.ai email it still holds.

## 0.1.13

- Settings › Agents says how each profile pays: Subscription, API billing, Amazon Bedrock, Google Vertex AI, Microsoft Foundry or a custom endpoint. The email shows only where that account is what pays, not the old claude.ai login a Bedrock or Vertex profile still holds.
- The Claude and Codex logos keep their own colors on every card, and the billing badge no longer cuts into them.
- The cache figure's icon sits level with the others on the tokens line.
- The cat sits in the middle of its tile in every coat and pose.

## 0.1.12

- Sessions already running when OpusBar starts show how they pay right away, instead of no badge until their next event.
- A session started from a shell that sets Bedrock, Vertex AI, Foundry or an API key is picked up at once, and its profile is remembered. OpusBar looks only at those few variable names; of a key it notes only that it is set, never its value.

## 0.1.11

- Every session card shows who runs it and how it pays: the Claude or Codex logo under the timer, with a small badge in its corner. Amazon Bedrock, Google Vertex AI and Microsoft Foundry get their own colored logos; a plan, an API key and a custom endpoint get a simple symbol. Hover for the name.
- A session started from a shell that sets Bedrock, Vertex AI or an API key now says so on its card, not only in the Usage tab.
- The project name gets the whole line, so long names show in full. The mode badge moved to the status line.
- Billed-per-use rows in the Usage tab use the same badged logo.

## 0.1.10

- A profile that runs on Amazon Bedrock, Vertex AI, Foundry or an API key only because your shell says so keeps its "Billed per use" row after its sessions end, and after OpusBar restarts. A plain session in that profile hands it back to its files.
- Billed-per-use rows name the profile folder, so two profiles signed in with one email (a Bedrock shell and a Pro login) are told apart.

## 0.1.9

- OpusBar knows how each Claude and Codex account is signed in. Accounts billed per use (an API key, a Console sign-in, a custom endpoint, Amazon Bedrock, Google Vertex AI or Microsoft Foundry) get a "Billed per use" card in the Usage tab instead of waiting for plan limits that never come.
- A session billed per use says so in its details.
- Codex accounts are named by their ChatGPT email instead of their folder.
- Sign-in types come from files on your Mac and from which variables a session sets, never their values. Nothing leaves your Mac.

## 0.1.8

- The menu resizes as soon as you open or close a session card. It used to keep its old height while open, so cards were cut off or left a gap until something else woke OpusBar.

## 0.1.7

- Opening and closing a session card is smooth: the details fade in and out with the card, the list follows in the same spring, and the menu no longer cuts a closing card off or shifts the list.

## 0.1.6

- Session cards fit the menu again: the tokens row no longer pushes cards and the update note past its right edge. Long figures tighten their spacing, then drop cache reads.
- The mode badge is outlined like the agent label beside it.

## 0.1.5

- Notifications when a session finishes are on by default.
- Settings > Notifications says when macOS is blocking notifications, or showing them without a banner, and takes you straight to the fix. A new button sends a test notification.
- Session cards show the mode each session runs in: Plan, Accept edits, Auto, Don't ask or Bypass.
- Session cards list live subagents: what kind, their task, the tool they're running and for how long.
- Session cards show tokens and cost: new input, output, cache reads and API cost, subagents included.

## 0.1.4

- Fixed a crash when opening the menu.
- Collapsing a session card fades its details out before the card shrinks, as expanding does.

## 0.1.3

- OpusBar asks for notification permission at launch and when you turn a notification on, so a missed prompt no longer swallows the first notice.
- Failed notification permission requests and posts are logged.
- The Agents pane no longer says running Claude sessions need a restart: they pick up the hooks from their next prompt.

## 0.1.2

- Updates now install themselves: OpusBar downloads and checks a new version in the background and swaps it in when you quit. Turn it off in Settings.
- After an update, the menu shows what changed once.

## 0.1.1

- Claude Code and Codex logos replace the colour dots in usage limits, the API value legend and Settings.

## 0.1.0

First public release.

- Live Claude Code and Codex sessions in the menu bar: needs you, working, thinking, done, error.
- The pixel cat: 21 coats, a pose per state, menu bar size and pace.
- Notifications when a session needs you, hits an error or finishes.
- Plan limits for every Claude Code and Codex account, with reset and 80% / 95% notifications.
- Usage and Spend: API value and tokens over 24 hours to 90 days, by agent, account, model and project.
- Updates from GitHub, checked against OpusBar's own signature.
