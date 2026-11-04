# Codex navigation prototype — findings (ADR 0.59.0, Sprint 1, step 3)

Throwaway SwiftUI prototype in `CodexPrototype/` (target `GreymereCodexProto`, bundle `com.greymere.ios.codexproto`, display
name "Codex Proto"). Dummy data only, generated in code (`ProtoData.swift`): 333 entries in the default "The Route" scope
(about 480 across all series): 57 characters, 189 locations (40 buildings, with floors and rooms inside, duplicates such as
several "Great Hall"s on purpose), 34 objects, 32 lore, 6 voice guides, 6 reference lists, 9 other; aliases on about half
the characters and some places. No network, no live API, no real Codex data. Delete the folder and the target after the gate.

Wireframes: `docs/wireframes/codex-wireframes.html`. Screenshots: `docs/codex-prototype-screenshots/`.

Run it:

```
xcodegen generate
xcodebuild -project Greymere.xcodeproj -scheme GreymereCodexProto -destination 'platform=iOS Simulator,name=iPad mini (A17 Pro)' build
```

Simulators used: iPad mini (A17 Pro) (an iPad mini 7), landscape and portrait; and an **iPhone 14 Plus created on the
iOS 27.0 runtime** (428×926 pt). The existing "iPhone 14 pro" sim is not a Plus.

## What was built (navigation only)

- **iPhone:** `NavigationStack`: Codex home (search at the bottom, series scope row, Recent, Browse by type with counts, Tools:
  Find missing, Ask Godric) → type list → entry. Typing replaces the home with ranked results (type chips with counts, a reason
  on each hit, "Ask Godric: …" at the bottom). ⋯ and ＋ top right.
- **iPad:** `NavigationSplitView`, list left and entry right in **both** orientations (columns fixed visible, so there is no
  sidebar button to find). Chip strip for All/types above the list. A ⋯ menu switch "iPad portrait drill-down" lets the
  author compare the phone pattern in portrait.
- **Entry:** hero (image state, aliases, "Appears in" books), "In: …" chips for every ancestor, **Contains** chips (rooms and
  floors, with counts, "+N more"), body, ⋯ menu (Edit, Dictate an edit, Standardise to template (locations only),
  Image…, Series/books/scope…, Delete with confirmation), Godric-context toggle, Edit button.
- **Edit → Review → Proposed change (diff) → Apply**, with a prototype switch ("pretend it was edited on another device")
  that bumps the entry version so **Apply is refused as stale**, shows the current text, and offers Re-propose on latest.
  Locked type for voice guides and reference lists.
- Stubs (reachable, built, **not screenshot-verified**, see below): Image sheet (craft prompt, generate with cost
  confirmation, use/regenerate/discard, approve/reject/delete, photos/camera rows), Series and books pickers (collapsible
  per series), Standardise (lands on the same proposal screen), Find missing (book picker, scan, open/created/dismissed,
  Develop, Dismiss, Link… as a search picker), Ask Godric (dummy answer with citation chips opening entries), New entry.

## Update: glass bar always present (author requirement)

The prototype now runs inside a stub shell (`ProtoShell.swift`) that imitates the real app's floating glass bar and workflow
tray: Home, Ask Godric, Panels, on every Codex screen, iPhone and iPad. Panels → Codex enters the panel (Codex is the only live
tile). With an entry open the bar gains an **Edit** pill and Ask Godric becomes **Godric**, taking the open entry as context
(the old eye toggle and bottom toolbar are gone). Phone search moved to the top. Screenshots: phone-09-shell-tray,
phone-10-shell-entry-bar; iPad portrait shows the bar on the stub Home. The bar floats over list content (rows scroll under
it), as in the real app. Home and Godric are stubs.

## Update 2: filter pull-down, top right left free, iPad follows the phone

Author feedback: the type chips should be a pull-down; the top-right menu clashes with the app's Settings gear; the iPhone
portrait navigation is better than the iPad's. Changes:
- Type chips are gone. One **filter button top left** opens a pull-down: Show (All and each type, with counts), Series,
  Show contained places, Find missing, Ask Godric about the Codex. It is the same menu on iPhone and iPad (phone-11).
- The top-right ⋯ and ＋ are gone, so the top right is free for Settings. **New** is a pill in the glass bar on list screens
  (Edit replaces it on an entry): phone-12.
- The phone home no longer has a Tools section (they are in the menu).
- **iPad portrait now defaults to the iPhone drill-down** (the switch in the menu still flips back to two panes). iPad
  landscape keeps the split. Verified on the iPad mini in portrait: the phone-style home with the glass bar and New pill (ipad-portrait-02-drilldown-home). Landscape split not re-checked.
- New observation: the menu is long (nine type rows plus series plus tools) and scrolls on a phone; the series choices
  could become a submenu or move to the scope row.

## Update 3: landscape keeps the portrait menu on the left, panel on the right (iPad and iPhone)

Author direction: turning to landscape keeps the same menu on the left and the working panel on the right, on both devices.
Landscape (width > height) is now one layout everywhere: the portrait navigation (search, series, Recent, Browse by type,
drill into a type list) in a 360 pt left column, the entry panel on the right; selecting a row fills the panel instead of
pushing. Portrait stays the drill-down. The old two-pane list and the iPad portrait switch are gone. Screenshots:
ipad-landscape-03-menu-left-panel-right, phone-landscape-01-menu-left-panel-right.
Open points: the entry's ⋯ menu is still top right and will clash with the Settings gear (move it into the bar or the
filter menu); the Panels tray overflows the top of an iPhone in landscape (it is the real app's tray design, 428 pt tall
screen); on the phone in landscape the left column is short, so the glass bar covers its lower rows; Find missing and Ask
Godric push inside the left column in landscape.

## Update 4: entry actions in the bar and the top-left menu; glass pills

- The entry's top-right ⋯ is gone (top right is free for Settings). Its actions (Edit, Dictate an edit, Standardise
  (locations), Image…, Series/books/scope…, Delete) are now in **both** places: a round **⋯ glass button in the bar**
  beside Edit and Godric, and a **"This entry" section at the top of the top-left filter menu** while an entry is open.
  Both call the same code. Bar on a phone in portrait with an entry open: Home, Edit, ⋯, Godric, Panels (fits on the
  Plus; tight on a smaller phone).
- The series row, the "Godric is looking at…" row and the Contains / In: chips are now liquid glass (same
  `glassEffect` and tint as the bar), so the left column matches the rest of the app. The list cards (Recent, Browse by
  type, results) are still standard grouped-list rows. Screenshots: phone-13, phone-14. Not re-checked on the iPad.

## Update 5: glass list rows; landscape full screen and a draggable column

- The Recent, Browse by type, type-list and result rows are now liquid-glass cards (same glass and tint as the bar; the
  selected row in landscape takes an accent tint), not flat grouped-list rows.
- Landscape (iPad and iPhone): a thin **drag strip** between the menu and the panel resizes the left column (260 pt up to
  60% of the width, default 360). A round glass button on the strip toggles **full screen** (panel only, menu hidden); the
  button stays at the left edge to bring the menu back. Double-tapping the strip does the same. The width is kept while the
  app runs (not saved across launches).
- Verified: iPad mini landscape (drag 360 to about 430 pt; full screen on Harrow Hall) and iPhone 14 Plus landscape (glass
  rows, strip, button). Not verified: dragging on the iPhone, restoring from full screen after the last nudge of the button,
  rotating while in full screen. Screenshots: ipad-landscape-04, ipad-landscape-05, phone-landscape-02.
- Observation: the full-screen button sits near the search field's right end; it may want to move once Settings and the
  real top bar exist.

## Update 6: landscape full screen and column width (design agreed by the author)

Landscape (iPad and iPhone): the menu on the left, the entry panel on the right. A thin strip between them drags the
column width (260 pt up to 60% of the screen); an inline icon at the top-left of the panel, left-aligned with the entry
picture, toggles full screen (the panel only). List rows, the series row and the Godric row are liquid-glass cards.
Notes for the real build, learned the hard way (screen-recorded on the iPhone 14 Plus):
- **Do not use the UIKit nav bar for the panel's top row on iPhone.** It re-applies the notch's side safe area a beat
  after the panel reaches the screen edge, so the title and icon jump left about 0.3 s after the animation. A plain
  SwiftUI header moves with the layout. (The iPad has no side inset, so it never showed.) Pushed screens still use the nav bar.
- **Keep the menu alive in full screen** (collapse and fade it, panel slides over it) instead of removing and rebuilding
  it: its drill-down position, scroll and search then come back untouched.
- Prototype-only launch flags `-startCodex` and `-autoToggle` exist so the timing can be screen-recorded
  (`xcrun simctl io <device> recordVideo`).
- Not verified: full screen with a pushed entry open; iPad after the last change; real-device timing.

## What the screenshots show

| File | Shows |
|---|---|
| phone-01-home | search-first home, scope row, recents, browse by type with counts |
| phone-02-search-alias | "captain": Marenne Voss first, matched by alias "Captain Tam", type chips with counts |
| phone-03-entry-character | a character entry (aliases, appears-in books) |
| phone-04-location-contains | Harrow Hall with Contains chips (Great Hall, Second Floor (1), Cellars (3), East Stair) |
| phone-05-room-in-chips | The Tamarind Room three levels in, with "In: Harrow Hall" and "In: Second Floor" chips |
| phone-06-entry-menu | the ⋯ menu (Edit, Dictate, Standardise, Image, Series/books, Delete) |
| phone-07-proposal-diff | a dictated sentence as a diff with Apply and Discard |
| phone-08-stale-refused | Apply refused as stale, with "Re-propose on latest" |
| ipad-landscape-01-list / -02-entry-split | split view, list plus entry, chips and recents |
| ipad-portrait-01-split | portrait keeps both panes (list about 295 pt, entry about 450 pt) |

Note that phone-02 (and earlier text) used the code before the row change that moves "alias: …" onto its own line.

## Navigation problems found

1. **Short queries drown aliases.** "tam" matched about nine "Tamsin …" names and the Tamarind Room before "Captain Tam"
   (an alias). Ranking fixed in the prototype (exact name, exact alias, whole word in name or alias, word prefix, substring,
   then body text), after which "captain" puts the alias hit first. Needs the same ranking on the server, or done client-side
   over the aliases list. Body text matches then dominate long queries ("captain" also matched six characters whose role
   text contains it): consider showing name/alias hits and text hits in separate sections.
2. **"In: …" chips push, not pop.** From a room, tapping "In: Harrow Hall" pushes a second Harrow Hall onto the stack, so the
   back stack grows (Harrow → Floor → Room → Harrow). In the real build up-chips should pop to the existing screen, or
   replace the top of the stack.
3. **Chip strip does not fit.** On the iPad list column (≈300–330 pt) only "All · Characters · Locations" are visible; Objects,
   Lore, Voice, Lists, Other need horizontal scrolling. Recommend a type Menu (one button, "All 333 ▾") on iPad, chips
   only on the phone results screen.
4. **Tools sit below the fold** on the phone home (under the 7 type rows and the floating search bar). Find missing and Ask
   Godric are better in the ⋯ menu or as two buttons above Browse by type.
5. **iOS 26 bottom bar hides labels.** The entry's bottom toolbar renders icon-only (an eye and a pencil), so "Godric is
   looking at this" is not self-explanatory. Use a labelled pill in the content (or the toolbar title area) in the real build.
6. **Recents reorder under the finger** on iPad: selecting Harrow Hall moves it to the top of Recent while the highlight
   follows it. Minor; freeze Recent while the list is on screen or drop Recent from the iPad list.
7. **Locations count (189) includes folded rooms** while the list shows 40+ buildings; the footnote explains it, but the
   chip and the row count disagree at a glance. Consider "Locations 189 (49 shown)".
8. **Simulator behaviour, not app bugs:** a tap right after a screenshot or after launch was often ignored once, and
   screenshots lag one action. Taps issued after a no-op action registered reliably.

## Not verified (said plainly)

- Image sheet, Series and books, Standardise, Find missing, Ask Godric and New entry **compile and are wired but I did not get
  clean screenshots of them**; driving them through the simulator was unreliable. On the iPad the Ask Godric sheet opened and
  then closed after I typed into it (cause not found: it may be the simulator's keyboard handling or a real dismissal bug).
  Treat those screens as unverified before the author gate; the wireframes show their intended design.
- iPad portrait drill-down toggle and the scope switch (series) were not exercised.
- No performance measurement beyond: the 480-entry search and list were instant in the simulator. Real-device timing is untested.

## What the author should try

1. iPhone: type `captain`, `tam`, `orange` (alias of a room), `ansel`; check the first result is the one you meant and why.
2. Browse by type → Locations: flip "Show contained places", then open Harrow Hall → Second Floor → The Tamarind Room → back.
   Is the "In:" chip or the back chevron what you reach for?
3. Entry → ⋯ → Dictate an edit → Review → Apply; then again, using the hammer menu to force a stale Apply.
4. iPad landscape and portrait: is the two-pane list enough, or do you want drill-down in portrait (⋯ → prototype switch)?
5. Anything you reach for that is not where you looked first (the Tools row, the ⋯ menu, Godric context).

## Next, if the navigation is approved

The real build replaces `ProtoData` with `/api/codex` (needs aliases in the list payload and a stale-write guard on the
save, both in the server repo), keeps `CodexStore`'s ranking as the client-side search, and reuses `HomeModel`-style models.
