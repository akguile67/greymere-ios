# Structure navigation prototype — findings (ADR 0.60.0, Sprint 2, step 2)

Throwaway SwiftUI prototype in `StructurePrototype/` (target `GreymereStructureProto`, bundle `com.greymere.ios.structureproto`,
display name "Structure Proto"). Dummy data in code (`ProtoData.swift`), no network. Delete the folder and target after the
author gate. Wireframes: `docs/wireframes/structure-wireframes.html` (approved at 5a32097; phone is the **iPhone 14 Pro,
393×852 pt**, corrected from the 14 Plus). Screenshots: `docs/structure-prototype-screenshots/`.

```
xcodegen generate
xcodebuild -project Greymere.xcodeproj -scheme GreymereStructureProto -destination 'platform=iOS Simulator,name=iPad mini (A17 Pro)' build
```

Run on the iPad mini (A17 Pro) simulator (landscape, and one portrait rotation) and the iPhone 14 pro simulator.
The wrench menu top right is prototype-only: simulate a live refresh, arm a stale-write clash, reset data.

## What was built and checked in the simulator

| Wireframe | Result | Screenshot |
|---|---|---|
| A board, one act open, synopsis closed with Show | works (phone, iPad) | ipad-landscape-01, phone-01 |
| B empty state, C book picker | works | phone-09, phone-08 (picker menu open) |
| D chapter pushed, summary on top, six collapsible sections | works | phone-02, ipad-landscape-02 |
| G add chapter by title, later chapters renumber | works (chapters after it in later acts renumber) | ipad-landscape-05, 06 |
| H delete, footprint, typed title (button stays disabled until it matches) | sheet works; typed match not exercised | phone-07 |
| I, L hold-and-drag within an act (phone and iPad) | works; numbers renumber | ipad-landscape-07, phone-06 |
| J cross-act drop refused with message | works on iPad (drop on Act 2) | ipad-landscape-08 |
| M, N, O Godric: sheet on phone, docked column on iPad, staged brief on the card with banner and Commit, codex proposal Apply/Discard | works | ipad-landscape-02, 03, phone-03..05 |
| Q stale-write sheet, whole-card choice with differing fields | works; Commit then "Use this device" saves | ipad-landscape-04 |
| P live refresh banner | built (wrench menu), not screenshotted |  |
| Rename, Draft button, Dictate | built as stubs, not exercised | |

## Findings: what the wireframes got wrong or left open

1. **Primary actions fall under the glass bar.** Commit briefing and Dictate sit at the foot of the card and the floating bar
   covers them: on iPad when sections are collapsed, on the phone as soon as the staged banner is shown. The Codex rule applies:
   put **Commit** (and Unlock / Draft) in the glass bar beside the Godric pill, the way Edit is for the Codex.
2. **Stale-write sheet is too tall for its own buttons.** At the medium detent, and even at large on iPad, "Use this device" and
   "Use the other device" are below the fold behind the list of fields. Pin the two choices above the list (or in a bottom bar).
3. **Godric thread does not scroll to the newest item.** At medium height on the phone the staged-brief card and the codex
   proposal (Apply/Discard) are below the fold and the thread stays at the top. Scroll to the last message on send.
4. **Duplicate summary.** The summary at the top of the card and the first section (Summary headline) show the same text. The
   wireframe question stands: either the top summary is the headline and the section list is the other five fields, or the top
   one is something else. As built it reads as a bug.
5. **The ⋯ menu top right collides with the app's Settings gear.** The wireframe draws ⋯ (Rename, Delete) top right of the chapter,
   but that corner belongs to the gear (floating-menu decision). Rename and Delete should move into the bar's ⋯, as in the Codex.
6. **An open act takes the whole phone screen.** With five chapters, Act 1 fills the screen and Acts 2 to Epilogue are below the
   fold; the status line scrolls away. Consider a compact chapter row, or a sticky act header. One-act-open works, but it is long.
7. **Add chapter sheet cannot show the renumbering before you commit it.** The wireframe drew the "after" cards; the sheet only
   says it in words. After the add, the effect is visible only in the board (and in a later act, off screen). A one-line preview
   ("Chapters 7 to 9 become 8 to 10") would answer it.
8. **Drag gives no visible landing slot or auto-scroll that I could verify.** The system lift preview works and the drop lands in
   the right place, but I could not capture the mid-drag state, and the prototype does not highlight a slot (a stuck purple drop
   highlight also showed after a drag). A long act on the phone may need edge auto-scroll while dragging; untested. Test on the device.
9. **A drop on a closed or different act is silent until it lands.** There is no live "not allowed" hint while dragging over another
   act; the refusal only appears after the drop. Acceptable, but a dim state (as drawn) while dragging would be clearer.
10. **Rotation drops the open chapter.** Turning the iPad from landscape to portrait returned to the board and closed the card
    (the prototype clears selection when the layout changes). The real app must keep the open chapter across rotation. Godric
    switched from the docked column to a sheet correctly.
11. **Taps in the strip under the floating bar are lost.** The bar's full-width container swallowed a tap on "Add chapter" when it
    sat behind it at the foot of the board. Give the scroll content a bottom inset equal to the bar, and keep the bar's hit area to
    its three buttons.

## Not verified here

Rename sheet, Draft into Creation, dictation, the live-refresh banner, typing a title to enable Delete, the phone stale sheet,
iPad portrait drill-down beyond the rotation above. All are plain stubs; the navigation to them is in place.
