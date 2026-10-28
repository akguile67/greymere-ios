# Desktop Home — exit checklist for iOS 0.1.0

Captured **28 October 2026**, the day card 0.50.0 started (ADR 0.50.0, "Parity
rule"). This is the fixed target: later changes to the desktop Home become
parity items for a later card, not changes to this list.

Source: the desktop Home on dev (prod data, 0.50.0) and its Book Details screen.
"Read-only" means the app shows it and nothing can be changed from the phone.

## In 0.1.0 (the four things the card names, plus what they rest on)

### A. Connection (not on the desktop Home; the app's own)
- [ ] A. Connect screen takes the server address and remembers it.
- [ ] A. Reads `GET /api/instance`: server version and environment.
- [ ] A. Environment banner: **PROD**, **PRE-PROD** or **DEV**, with the server version, always visible.
- [ ] A. Theme follows the server's theme (`GET /api/theme`).
- [ ] A. Server older than the app's minimum: a message naming both versions; Home is not loaded.
- [ ] A. Server unreachable (e.g. Tailscale off): its own message, different from the version one, with a Try again button.

### B. RAG cards (the row of cards across the top)
- [ ] B1. Cards in this order: Portfolio, Finance, Marketing, Legal.
- [ ] B2. A card for an area the author has switched off (Legal today) is not shown; the others share the row.
- [ ] B3. Each card: a coloured band (blue, green, amber or red), the area's name, and one sentence.
- [ ] B4. A card with no verdict yet reads "Awaiting first poll…", amber.
- [ ] B5. The sentence is the server's, word for word (today: "1 active book, comfortably ahead.").
- [ ] B6. Desktop opens the area's screen when a card is tapped. **Not on the phone in 0.1.0** (those screens are later cards); the card is shown, not tappable.

### C. The shelf
- [ ] C1. Title "The shelf" and the count of each group.
- [ ] C2. Three groups: **In plan**, **Seeds**, **Released**, in that order on screen; each ordered by most recent work, newest first.
- [ ] C3. Each item: its cover (a placeholder when it has none), its title.
- [ ] C4. Second line for a book in plan: the current step ("Act 1 drafted"). For a seed: "Seed". For a released book: its state.
- [ ] C5. Third line: how long since it was last worked on ("Today", "8 days ago").
- [ ] C6. A seed has no Book Details. A book in plan or released does.
- [ ] C7. Desktop's New book, New seed and Show archived buttons: **not in 0.1.0** (writes).
- [ ] C8. Desktop opens the reader (released), the working screen (in plan) or the seed's screen when a cover is tapped: **not in 0.1.0**; a cover opens Book Details.

### D. Book Details (read-only)
- [ ] D1. Cover, series name, title, first lines of the synopsis.
- [ ] D2. Badges: phase, health (BLUE / GREEN / AMBER / RED), word count, chapter count.
- [ ] D3. Five figures:
  - Manuscript: words written, with the target.
  - Editing: percent of chapters done, "x / y done", open issues.
  - Publish date, with days to publish.
  - **Variance to plan**: signed days (+ahead / −behind), "ahead of plan / behind plan / on plan / plan not committed", and the health word.
  - Contingency in plan: signed working days, the current step's name and date, its band.
- [ ] D4. "Book details" card: series, template, status, priority, chapter target, word target, actual word count, chapters, publish date, scheduling mode.
- [ ] D5. Full synopsis.
- [ ] D6. Overdue steps (from the portfolio; shown on the desktop Gantt and Godric's book line): the step, days late, and whether it waits on the author.
- [ ] D7. Everything above is the server's figure, unchanged; nothing is worked out on the phone.

### E. Devices
- [ ] E1. iPhone 14 Pro (real), iPad mini 7th generation, large iPad Pro (simulators and, when possible, the real iPads).
- [ ] E2. One set of screens that adapts by size; no "if iPad" anywhere.
- [ ] E3. Light and dark follow the server's theme side.
- [ ] E4. The app reports itself as iOS 0.1.0.

## On the desktop Home, **not** in 0.1.0 (parity items for later cards)

| Desktop element | Why not now | Where it goes |
|---|---|---|
| Today card: day/week arrows, due work, "available to pull forward" with Add to today, task list (tick, defer, re-size), "On offer from the studio", capacity bar, flags | Mostly writes; a read-only Today is its own piece of work | Card after Godric chat, or sooner on your word |
| The Daily Chronicle (Leah Tran's news briefing) | Not in the card's scope; shown only on days it is filed | Later |
| Daily Brief (Godric's five paragraphs) | **Your call** (below) | 0.1.0 if you say yes, else later |
| Godric panel on the right | iOS 0.2.0 | Card #305 |
| "All series" selector in the header | Not in the card's scope | Later |
| Left navigation rail (every other screen) | Each screen is a later card | Mobile roadmap #306 |
| Book Details: day planner strip, version history, identifiers (ISBN, ASIN), tracked links, Republish ebook, every edit pencil | Writes, or screens of their own | Later |

## Two things I need your word on

1. **Daily Brief.** The server already sends it and it is the story behind the coloured cards. I propose including it, read-only, under the cards. It is a small addition; say no and it waits.
2. **Tapping a card** (Portfolio, Finance…): I propose showing it as information only in 0.1.0, as above. The alternative is Portfolio opening the book list.
