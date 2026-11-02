# iOS 0.6.0 — Creation panel parity against the desktop Creation pane

Baseline: the desktop Creation pane at server 0.54.0 behaviour (`public/index.html`, `src/creation.js`), checked against the iPad app on branch `ios-0.6.0` (head at the time of writing: the commit that adds this file) against the dev server on :3000 (server 0.55.0).

**Status key**
- **Run** — built and run in the simulator (by me, or by the author where marked).
- **Built, not run** — code is in and compiles; never exercised in the simulator.
- **Not built** — absent.
- **Different** — deliberately not the same as the desktop.

Simulators used: iPad mini (A17 Pro) and iPhone 14 Pro. No real device. Dictation was only tried as start/stop, with no speech.

| # | Feature | Desktop behaviour | iPad status | Gap and where it goes |
|---|---|---|---|---|
| 1 | Chapter picker | Acts with "n/m drafted · k briefed", cards with beat and word counts, codex-gap triangle, "Brief in Structure first" when it cannot be drafted | **Run** (iPad and iPhone) | None |
| 2 | Chapter statuses | Draft one / Drafting / Briefed / Not briefed; "Draft one — locked" in the chapter | **Run** (picker). "Draft one — locked" text **built, not run** (no draft-one chapter opened) | None |
| 3 | Chapter badge numbering | Prologue and sections by name, body chapters numbered in book order | **Run** (Prologue, Ch 1–12 correct on The Route) | Different only for self-labelled titles that re-sync the count (done), none known |
| 4 | Book choice | Book bar | **Built, not run** beyond The Route (menu present; only one book is offered on dev besides The House) | None |
| 5 | Open a chapter | Prune empty beats, then read the chapter; a briefed chapter becomes drafting | **Run** | None |
| 6 | Prune empty beats on leaving | Yes | **Built, not run** (leave via Chapters / panel change calls it; not checked on the server) | None |
| 7 | Brief read | Five fields in a collapsible block | **Run** | None |
| 8 | Brief edit in place | Edit, saved by PATCH | **Run by the author** (editor opened; save not separately confirmed). Only changed fields are sent | Desktop saves on blur; iPad has Save/Cancel. Different, kept |
| 9 | Beat add | Place at caret or end, with what happens and target | **Run by the author** (sheet opens, beat added). "In the text" place with a paragraph stepper **built, not run** | None |
| 10 | Beat edit | In place, saved on blur | **Run by the author** (sheet opens; save not separately confirmed) | Sheet with Save, not in place. Different |
| 11 | Beat delete | Trash button | **Run by the author** (with confirmation) | Confirmation is iPad-only. Different |
| 12 | Beat reorder | Not a desktop feature as such (beats sit at their place in the text) | **Run** (Move up/down changed and renumbered the beats on the server) | iPad reorders the scene order, not the place in the text. Different; revisit in Bug Hotel if the author wants drag |
| 13 | Beat place label | "After paragraph N: “…”", "At the end of the chapter", "Before the first paragraph" | **Run** | None |
| 14 | References: propose | Godric proposes; "Resolving references…" chip | **Run by the author** | None |
| 15 | References: add, remove, link to an existing entry | Picker with codex entries or a new name; chip × ; red chip menu | **Run by the author** (add, dismiss). Link-to-entry and remove **built, not run** | None |
| 16 | References: dismiss and restore a walk-on | Yes | **Run by the author** (dismiss). Restore **built, not run** | None |
| 17 | References: "Create in World & Character" | Opens the W&C worklist | **Not built** | Deliberate: there is no W&C panel on the iPad. The stop block says to finish it on the laptop. Bug Hotel only when W&C comes to the iPad |
| 18 | Continuity block on a beat | "Yes — the story goes this way" / "Let me correct the brief" | **Built, not run** (no beat with a contradiction on dev) | None |
| 19 | Godric chapter chat | History, opening message, tools, memory | **Run** (iPad: loaded thread, sent a turn, thinking state; iPhone: sheet opens with the thread) | No History/New chat for a chapter (one thread). Different, matches the desktop |
| 20 | Beat-change card | Current vs proposed, Apply / Discard; Godric cannot apply it | **Run** on iPad: card with word-level diff, Apply changed the beat on the server | Discard button **built, not run**. Card at iPhone width **not re-checked** |
| 21 | Generate | Slow; button disabled and relabelled | **Run** ("Drafting…" with "about a minute"; request returned a stop). A completed draft was **not** produced in the simulator | None |
| 22 | Generate stop: codex gap | Gap list; dismiss; create/develop in W&C | **Built, not run as a screen**: the server did return a stop on dev, but I did not capture the stop block on screen. Dismiss and Link built; create/develop is "on the laptop" text | W&C exit is Different (see 17) |
| 23 | Generate stop: continuity | Accept or correct the brief | **Built, not run** | None |
| 24 | Draft on the beat | Draft text, word count, "nothing is in the chapter until you accept" | **Built, not run** (no draft was produced) | None |
| 25 | Accept | Lands in the manuscript at the beat's place, versioned | **Built, not run** | None |
| 26 | Regenerate | Generate again | **Built, not run** | None |
| 27 | Discard draft | Clears the draft | **Built, not run** | None |
| 28 | Undo last draft | Back to the version before; beat restored | **Built, not run**. Kept for the session only; cleared on a prose save, lock or leaving | Desktop keeps it until the page changes. Different, small |
| 29 | Prose editing with beats in place | Segments with beat cards between them | **Run** (edit on iPad, saved through the segment save; the rest of the text byte-identical; segments and beats stayed consistent) | None |
| 30 | Empty segment | n/a | **Run** ("Write here" opens an editor) | iPad-only affordance |
| 31 | Save indicator, explicit save | Autosave on the desktop | **Run** ("Unsaved edits", Save, Discard edits) | Different on purpose: the iPad saves explicitly, nothing is kept on the device |
| 32 | Save first-of-session | `begin_session` | **Built, not run** (sent on the first save; "Before editing" version not checked) | None |
| 33 | Stale-write conflict (CHAPTER_CHANGED) | Other text kept as a version if you overwrite | **Built, not run** (sheet with mine / current, Keep mine, Copy, Use current) | None |
| 34 | Beats-changed conflict (BEATS_CHANGED) | n/a on the desktop (it saves places itself) | **Built, not run** (copy my text, use current) | None |
| 35 | Empty chapter refusal (400) | Refused | **Built, not run** (banner, text kept) | None |
| 36 | Locked chapter (423, lock bar) | Read-only with a bar | **Built, not run** (no locked book on dev) | None |
| 37 | Structural actions while text is unsaved | Not applicable (autosave) | **Built, not run** (add, delete, move, accept, undo, lock, generate are refused until saved or discarded) | Different, needed because the segments change |
| 38 | Drafting notes: add on a selection | Select, press Note, write | **Built, not run** | None |
| 39 | Drafting notes: highlight, list, clear, reopen, delete | Margin list | **Built, not run** | None |
| 40 | "can't place" | Passage no longer found | **Built, not run** (matcher tolerates `*` and `_`) | Matching differs from the desktop's rendered-text match. Bug Hotel if it misfires |
| 41 | Lock as draft one | Two confirms (notes, then lock); pending beats stay | **Built, not run**. One dialog carries both messages | Different: one dialog. Minor |
| 42 | Lock refused when there is no prose | 400 | **Built, not run** (button disabled with no words) | None |
| 43 | Dictation in the Godric chat | Thumb button | **Run** (starts, shows the recording indicator, stops; iPhone) | No speech tested |
| 44 | Dictation into prose | Insert at the dictation point, never replace | **Built, not run**. Same `DictationModel` as the chat; ends on backgrounding or on changing segment | A chapter-length dictation test was **not** done. Dictated words do not scroll the page to the caret: Bug Hotel |
| 45 | Foreground refresh | Re-read on return | **Built, not run** (chapter, chat and notes re-read; edits are kept and the server catches a stale save) | None |
| 46 | Pull to refresh | n/a | **Built, not run** | iPad-only |
| 47 | iPad mini layout | Desktop | **Run** (picker, chapter, beats, Godric docked, text editing) | None |
| 48 | iPhone width | n/a | **Run** for the chapter view and the Godric sheet and chat input. **Not run**: beat cards, the Apply card, the conflict and notes sheets at phone width | Check before release |
| 49 | Version fields | n/a | App 0.6.0, minimum server 0.55.0 | None |

## Items not run in the simulator

Beats: link-to-entry, remove a reference, restore a dismissed reference, "in the text" placement of a new beat, edit-save confirmation, the continuity block.

Generation: a completed draft; Accept, Regenerate, Discard, Undo last draft; the stop block as a screen (gap and continuity).

Prose: the stale-write sheet, the beats-changed sheet, the empty-save and locked-chapter refusals, the first-save "Before editing" version, the locked-chapter bar and a draft-one chapter's "locked" text.

Notes and lock: adding a note, the highlight, the Notes list actions, "can't place", Lock as draft one, and the open-notes warning.

Dictation: dictation into prose, and dictation into a chapter-length field.

App: foreground refresh, pull to refresh, leaving a chapter (prune), the Godric Discard button, the Apply card and beat cards at iPhone width, and the book menu with more than one book.

## Gaps for Bug Hotel

- Dictated words do not scroll the page to the caret.
- Drag reordering of beats (the iPad has Move up/down only).
- "Create in World & Character" from a gap, until W&C reaches the iPad.
- "Can't place" matching is an approximation of the desktop's.
- A note cannot span two passages.
- Lock uses one dialog, the desktop uses two.
