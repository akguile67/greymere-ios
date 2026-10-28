# Desktop Home — exit checklist for iOS 0.1.0

Captured **28 October 2026**, the day card 0.50.0 started (ADR 0.50.0, "Parity
rule"). This is the fixed target: later changes to the desktop Home become
parity items for a later card, not changes to this list.

Source: the desktop Home on dev (prod data, 0.50.0) and its Book Details screen.
"Read-only" means the app shows it and nothing can be changed from the phone.

## In 0.1.0 (the four things the card names, plus what they rest on)

### A. Connection (not on the desktop Home; the app's own)
- [ ] A. The app remembers the server and connects by itself, going straight to Home. The address screen appears only on first run or if the server cannot be reached.
- [ ] A. Reads `GET /api/instance`: server version and environment.
- [ ] A. Environment banner: **PROD**, **PRE-PROD** or **DEV**, with the server version, always visible.
- [ ] A. Theme follows the server's theme (`GET /api/theme`).
- [ ] A. Server older than the app's minimum: a message naming both versions; Home is not loaded. A safety net, rarely seen.
- [ ] A. Server unreachable (e.g. Tailscale off): its own message, different from the version one, with a Try again button.

### B. RAG cards (the row of cards across the top)
- [ ] B1. Cards in this order: Portfolio, Finance, Marketing, Legal.
- [ ] B2. Suppression is the desktop's own: the server sends no card for an area switched off in Configurator → Suppression (Legal today), and the app draws only what it is sent. The app has no switch of its own.
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
- [ ] E2a. iPad: with nothing tapped, Home fills the screen as on the desktop; tapping a cover slides Book Details in on the right with Home still visible beside it.
- [ ] E3. Light and dark follow the server's theme side.
- [ ] E4. The app reports itself as iOS 0.1.0.

### G. Today (added to 0.1.0 on 28 October at your request; read-only)
Reads the three calls the desktop Today card reads (`/api/schedule/daily-list`, `/api/home/tasks`, `/api/home/flags`), so the two cannot disagree.
- [ ] G1. Title "Today — Wednesday 28 October" with Previous day, Today and Next day (days only; a future day is shown as the desktop shows it, projected).
- [ ] G2. Flags for the day, if any (text only; "Not today" is a write).
- [ ] G3. The day's work: "Nothing in the plan is due today — you're ahead on every book." when nothing is due; otherwise each book's due work with its hours, and the "books want Nh of a Nh day" line when the day is oversubscribed; a non-working day or a clear day says so.
- [ ] G4. "Available to pull forward": book, step, amount, hours, "not needed for N working days · plan has it from <date>" (the Add to today button is a write, not shown).
- [ ] G5. Task list: "N to do · N done today", each task with its size, hours, who raised it, "deferred to here — reason" or "since <date>"; a ring or tick shows done or not (not tappable).
- [ ] G6. "N deferred", closed until tapped, then each with its return date and reason.
- [ ] G7. "On offer from the studio": area, title, source, reason, hours and how they were sized, "N more waiting" (Add to today and Pin first are writes, not shown).
- [ ] G8. Capacity: "Nh committed of Nh available", the bar, "Nh still free" or the over-capacity warning, and the production/tasks split.
- [ ] G9. Refreshed by pulling down and each time the app comes back to the front.

### H. Added after the second review (28 October)
- [ ] H1. Shelf groups are floating cards, like Today and the status cards, so the whole screen looks consistent.
- [ ] H2. A shelf group's covers wrap onto new lines instead of scrolling sideways; a group can be collapsed (remembered on the device).
- [ ] H3. Book Details opens beside Home only when the screen is at least 900 points wide (iPad on its side, iPad Pro); on a narrower screen (iPhone, iPad mini upright) it is a screen of its own with a back button.
- [ ] H4. When beside Home, the divider can be dragged to give either side more room (remembered).
- [ ] H5. Nothing on any screen is wider than the screen (Today's header wraps on a phone).

### I. Added after the third review (28 October)
- [ ] I1. The environment pill sits on a glass band across the top; the page scrolls behind it.
- [ ] I2. Today is a collapsible panel like the shelf groups (collapsed state remembered).
- [ ] I3. Collapsed shelf groups share the row evenly and fill the full width.
- [ ] I4. Book Details figures are equal-size tiles in tidy rows (three over two on a wide panel; two, two and one on a narrow one).
- [ ] I5. Beside Home, the details have an expand button (arrows) that gives them the whole screen, and the same button brings Home back.
- [ ] I6. Nothing is wider than its column: rotating, collapsing, going back from details or dragging the divider never pushes content off the screen.

### J. Added after the fourth review (28 October)
- [ ] J1. Shelf rows are laid out explicitly and always fill the width: open groups stretch to share it (their covers stay left-aligned, never squeezed below their natural width), collapsed groups beside an open one stay pill-sized, and a row of only collapsed groups shares the width evenly.

## On the desktop Home, **not** in 0.1.0 (parity items for later cards)

| Desktop element | Why not now | Where it goes |
|---|---|---|
| Today: tick, defer, re-size, Add to today, Back to offers, Pin first, Not today, estimate buttons | Writes | Later card, each with its own risk review |
| Today: Week view | Not asked for yet | Later |
| The Daily Chronicle (Leah Tran's news briefing) | You no longer use it and are retiring it | Not built |
| Daily Brief (Godric's five paragraphs) | You no longer use it and are retiring it | Not built; removed from the server summary |
| Godric panel on the right | iOS 0.2.0 | Card #305 |
| "All series" selector in the header | Not in the card's scope | Later |
| Left navigation rail (every other screen) | Each screen is a later card | Mobile roadmap #306 |
| Seeds: opening a seed's own screen | A seed's screen is a conversation | Later |
| Book Details: day planner strip, version history, identifiers (ISBN, ASIN), tracked links, Republish ebook, every edit pencil | Writes, or screens of their own | Later |

## Decided (28 October)

- Daily Brief and Daily Chronicle: not in the app; you plan to retire them on the desktop.
- Cards are information only in 0.1.0.
- Suppression follows the desktop; the app has none of its own.
- Today is in 0.1.0, read-only (your call after the first simulator review).
