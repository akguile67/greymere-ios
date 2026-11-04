# Release iOS 0.10.0: the Structure panel

*ADR 0.60.0 (platform card 0.60.0). Written from the build, 4 November 2026. Needs server 0.60.0 (the app refuses an older one). Installed on the iPhone 14 Pro and iPad mini as Greymere Dev and checked there against The Route on the dev server. Not yet installed as the pre-production or production app.*

## What it does

- **Structure on your iPad mini and iPhone.** Each act shows its badge, counts and what is outstanding, with its synopsis one tap away (read-only; it changes in Ideation). The chapters sit under it as cards, as in Creation, each saying Drafted, Drafting, Briefed, Active or Not briefed, with a triangle where the Codex is missing an entry.
- **Brief a chapter.** Touch a card to open it: a summary headline, then setting, who, what happens, what the reader learns and what it achieves as sections that open and close. Fields save as you leave them; Commit makes the briefing Briefed; Unlock briefing to edit reopens it. Draft opens the chapter in Creation, which offers a way back to Structure.
- **Add, rename, delete, reorder.** Add a chapter to an act by title; later chapters renumber. Rename from the ⋯ menu. Delete shows what it takes with it and needs the title typed. Hold a card and drag it to reorder within its act; another act refuses with a message.
- **Godric.** The one Structure conversation for the book, with the open card as context. A brief he stages lands on the card for you to edit and Commit; a codex entry he drafts shows as a diff you Apply or Discard. Docked beside the panel on an iPad, a sheet on an iPhone.
- **Devices follow each other.** A change on the laptop or the other device appears at once. If a chapter changed elsewhere while you were editing, a sheet shows the fields that differ and you choose this device or the other for the whole card.

## Differences from the plan

- The navigation was built and approved on a throwaway prototype first (`docs/structure-prototype-findings.md`).
- The card grid follows Creation rather than the one-act-at-a-time accordion drawn first; Commit and Draft are in the glass bar.

## Not in this release

Editing, locking or unlocking an act synopsis, Validate structure, Godric History and New chat for this thread, and the two desktop-only generators. See `docs/structure-exit-checklist.md` and Bug Hotel #328 to #332.

## Not tested

The empty state (no locked synopsis); the way back to Structure from Creation; the production and pre-production iOS builds (server 0.60.0 is not on them yet). The desktop does not refresh itself when iOS changes Structure; it shows the change after a reload.
