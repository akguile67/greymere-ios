# Structure panel exit checklist, iOS 0.10.0 (platform card 0.60.0)

*Against `docs/structure-parity-checklist-0.60.0.md` in the server repo (signed off 4 November 2026) and Addendum 1 of ADR 0.60.0.
Written from the build on 4 November 2026. "Seen" means the author ran it on the iPad mini and iPhone against The Route on the dev
server; "built" means it compiles and is installed but was not run.*

## Shipped and seen

| # | What | Notes |
|---|---|---|
| 1.1 | Book picker | One book in the plan, so only the picker itself was seen |
| 1.2 | Status line, "n / N acts drafted" | |
| 1.4 to 1.7 | Acts in order with badge, counts, what is outstanding | |
| 2.1, 2.5, 2.7 | Act synopsis, read-only, closed until Show, with its lock state | Markdown (bold, italic) shown as written. No edit, Lock or Unlock |
| 3.1, 3.8, 3.9 | Chapter cards in a grid as in Creation: badge, title, summary, state, codex-gap triangle | State reads Drafted or Drafting once Creation has the chapter, otherwise Briefed, Active or Not briefed |
| 3.2 | Rename (from the ⋯ menu) | Seen on the phone and the laptop |
| 3.3 | Add a chapter to an act, by title | Later chapters renumber (server 0.60.0) |
| 3.4 | Delete with the footprint and the typed title | The title match is case-sensitive; seen cleared on both devices |
| 3.5 | Hold and drag to reorder within an act (phone and iPad); another act refuses with a message | |
| 3.6, 3.7 | Touch a card to open it; the six fields as sections that open and close | |
| 3.10, 6.4 | Draft opens Creation on that chapter | Creation shows a "Structure" way back when it was opened this way |
| 4.1 to 4.4 | The briefing: summary headline and five sections, saved on leaving a field, Commit, Unlock briefing to edit | Commit, Draft and the chapter menu sit in the glass bar |
| 5.1 to 5.3, 5.5 | Godric's one thread per book, with the open card as the hint; a staged brief lands on the card for Commit | Docked on iPad, a sheet on iPhone |
| 5.6 | A codex entry Godric drafts appears as a diff with Apply and Discard | Apply seen; the entry reached the Codex |
| 5.9 | Dictation in the Godric box | Existing chat component |
| 7.2 | Live refresh: a change on another device appears without a manual refresh | Seen on the phone and iPad |
| 7.3 | Stale-write sheet: one choice for the whole card, listing the fields that differ | Seen; "Use this device" wrote its text over the laptop's |

## Built, not run by the author

- The empty state (a book with no locked synopsis); The Route is the only book in the plan.
- The "Structure" way back inside Creation (added on the last build).
- The commit refusal when every field is empty.

## Not shipped (decided)

| What | Why |
|---|---|
| Edit, Lock and Unlock of an act synopsis | The synopsis changes only in Ideation |
| Validate structure | Deferred (Bug Hotel #328) |
| Godric History and New chat for the Structure thread | Deferred (Bug Hotel #329) |
| Generate synopsis from manuscript, Generate briefs from prose | Dropped (Bug Hotel #330) |
| Dictate button on a card | The keyboard's own dictation works in the fields |

## Differences from the wireframes

- The navigation was built and approved on a throwaway prototype first (`docs/structure-prototype-findings.md`).
- The board is a card grid with every act showing, as Creation does, replacing the accordion with one act open at a time; a card opens in place of the board with a way back. No iPad split.
- The summary headline is the top block of the card and the other five fields are the sections, so nothing shows twice.
- Commit, Draft and the chapter menu are in the glass bar, not at the foot of the card or top right.
- Selectable text was removed from the synopsis and read-only fields: on a real device it swallowed the tap that collapses them.

## Server work, done in server 0.60.0

1. A `version` on every chapter card and an `order_version` on every act.
2. Optional `base_version` and `base_order_version` on rename, brief save, commit and reorder (409 `{error:'stale', current}`).
3. `structure.changed` on the event stream after any Structure write.
4. Chapter numbers stay one sequence through the book; a chapter added to an act goes at the end of that act (commit 6285152).

The desktop Structure panel is unchanged, so it does not refresh on `structure.changed`: a change made on iOS shows there after a reload.
