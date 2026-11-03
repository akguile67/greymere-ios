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
  landscape keeps the split. Not re-screenshotted on the iPad after this change.
- New observation: the menu is long (nine type rows plus series plus tools) and scrolls on a phone; the series choices
  could become a submenu or move to the scope row.

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
