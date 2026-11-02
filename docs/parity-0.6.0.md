# iOS 0.6.0 — Creation panel parity against the desktop Creation pane

Baseline: the desktop Creation pane at server 0.54.0 behaviour (`public/index.html`, `src/creation.js`). iPad app on branch `ios-0.6.0`, head before this update `0671a37`, against the dev server on :3000 (server 0.55.0). First written at `fdfb6c3`; updated after the author's simulator runs.

**Status key.** *Run*: exercised in the simulator by me or by Andy (named per row). *Built, not run*: code is in and compiles, never seen in the simulator. *Not built*: absent. *Different*: deliberately unlike the desktop (the row says whether it was run).

Simulators: iPad mini (A17 Pro) and iPhone 14 Pro. No real device. Rows were upgraded only on what was seen in the simulator, never on the code.

**Counts: 79 rows. Run 35 · Built, not run 31 · Not built 2 · Different 11.**

| # | Feature | Desktop behaviour | Status | Evidence | Gap or note |
|---|---|---|---|---|---|
| 1 | Chapter picker: acts, counts, codex-gap triangle, "Brief in Structure first" | Acts with "n/m drafted · k briefed"; cards with beat and word counts | Run | Me on iPad mini and iPhone; Andy on iPad mini | — |
| 2 | Chapter statuses in the picker | Draft one / Drafting / Briefed / Not briefed | Run | Me on iPad mini and iPhone | — |
| 3 | "Draft one — locked" text in an open chapter | Shown for a locked chapter | Built, not run | No draft-one chapter opened | — |
| 4 | Chapter badge numbering | Prologue by name, body chapters numbered in order | Run | Me on iPad mini and iPhone | — |
| 5 | Book menu with more than one book | Book bar | Built, not run | Only The Route used | — |
| 6 | Open a chapter (prune, read, briefed becomes drafting) | Yes | Run | Me and Andy, iPad mini and iPhone | — |
| 7 | Prune empty beats on leaving | Yes | Built, not run | Not checked on the server | — |
| 8 | Brief read | Five fields in a collapsible block | Run | Me and Andy | — |
| 9 | Brief edit and save | Edited in place, saved on blur | Built, not run | Andy opened the editor; the save was not confirmed | Different by design: Save/Cancel and only changed fields are sent |
| 10 | Brief opens collapsed | Desktop remembers its last state | Different | Run by Andy on iPad mini | Author's request: opens closed so the prose is first |
| 11 | Beat add at the end | Place at caret or end | Run | Andy on iPad mini | — |
| 12 | Beat add "in the text" (paragraph stepper) | Place at the caret | Built, not run | — | — |
| 13 | Beat edit | In place, saved on blur | Different | Run by Andy on iPad mini | Different by design: a sheet with Save |
| 14 | Beat delete | Trash button | Run | Andy on iPad mini | iPad adds a confirmation |
| 15 | Beat reorder | Beats sit at their place in the text; no reorder control | Different | Run by me and Andy on iPad mini | Move up/down reorders the scene order. Drag reordering goes to Bug Hotel |
| 16 | Beat place label | "After paragraph N: …", end, before first | Run | Me on iPad mini | — |
| 17 | References: propose | Godric proposes; "Resolving references…" | Run | Andy on iPad mini | — |
| 18 | References: add and remove | Picker; chip × | Run | Andy on iPad mini | — |
| 19 | References: link a name to an existing entry | Red chip menu | Built, not run | — | — |
| 20 | References: dismiss a walk-on | Yes | Run | Andy on iPad mini | — |
| 21 | References: restore a dismissed name | Yes | Built, not run | — | — |
| 22 | References: Create in World & Character | Opens the W&C worklist | Not built | — | Deliberate: no W&C panel on the iPad. Bug Hotel when W&C reaches the iPad |
| 23 | Continuity block on a beat | Accept or correct the brief | Built, not run | No contradiction on dev | — |
| 24 | Godric chapter chat: load, send, thinking state | Yes | Run | Me on iPad mini; thread loaded on iPhone | — |
| 25 | No History / New chat for a chapter | One thread per chapter | Different | Seen by me on iPad mini | Matches the desktop |
| 26 | Beat-change card and Apply | Current vs proposed; Godric cannot apply | Run | Me on iPad mini (beat changed on the server) | — |
| 27 | Beat-change Discard | Yes | Built, not run | — | — |
| 28 | Beat-change card at iPhone width | n/a | Built, not run | — | — |
| 29 | Generate (slow; button disabled and relabelled) | Yes | Run | Andy on iPad mini and iPhone | — |
| 30 | Generation stop: codex gap, with dismiss and link | Gap list; exits | Built, not run | The server returned a stop once; the block was never seen on screen | — |
| 31 | Generation stop: continuity | Accept or correct the brief | Built, not run | — | — |
| 32 | Generation stop exit: create or develop in World & Character | Opens W&C | Not built | — | Deliberate: text says to finish it on the laptop |
| 33 | Draft shown on the beat | Draft, word count, "not in the chapter until you accept" | Run | Andy on iPad mini and iPhone | — |
| 34 | Accept | Lands in the manuscript at the beat's place, versioned | Run | Andy on iPad mini and iPhone | — |
| 35 | Regenerate | Generate again | Run | Andy on iPad mini | — |
| 36 | Discard a draft | Clears the draft | Built, not run | — | — |
| 37 | Undo last draft | Back to the version before; beat restored | Built, not run | — | Kept for the session only, cleared on a save, lock or leaving |
| 38 | Prose editing with beats in place | Segments with beat cards between | Run | Me on iPad mini (saved; rest of the text unchanged) | — |
| 39 | Empty passage: "Write here" | n/a | Run | Me on iPad mini | iPad-only |
| 40 | Unsaved indicator and explicit Save | Desktop autosaves | Different | Run by me on iPad mini | Different by design: nothing is kept on the device |
| 41 | Add, delete, move, accept, undo, lock, generate refused while text is unsaved | n/a | Built, not run | — | Needed because the segments change |
| 42 | First save of a session sends begin_session | "Before editing" version | Built, not run | Version not checked | — |
| 43 | Save refused: chapter changed (CHAPTER_CHANGED) | Other text kept as a version if you overwrite | Run | Me on iPhone 14 Pro: typed on the phone, saved from a second writer (a PUT to the server) first, pressed Save. Sheet shown with the device wording; "Take the saved version" loaded the saved chapter and put the phone text on the clipboard | "Keep this device's version" (the overwrite and the Version history copy) was not run in this pass. No Merge, by design. Not seen on iPad mini |
| 44 | Save refused: beats changed (BEATS_CHANGED) | Not a desktop case | Built, not run | Reworded ("Take the saved chapter", copies this device's text first); the sheet was not triggered | — |
| 45 | Save refused: empty chapter (400) | Refused | Built, not run | — | — |
| 46 | Locked chapter: read-only with bar | Read-only with a bar | Run | Me on iPhone 14 Pro: The House (published) chapter 1 on dev. Prose read-only, bar shown | Not seen on iPad mini |
| 47 | Drafting note: add on a selected passage | Select, press Note, write | Run | Andy on iPhone | — |
| 48 | Drafting notes: view the list | Margin list | Run | Andy on iPhone | — |
| 49 | Drafting note: delete | Yes | Run | Andy on iPhone | — |
| 50 | Drafting note: clear and reopen | Yes | Built, not run | — | — |
| 51 | Drafting note: highlight in the text | Yes | Built, not run | — | — |
| 52 | Drafting note: "can't place" | Passage changed | Built, not run | — | Matcher approximates the desktop's |
| 53 | Lock as draft one, with warning for open notes | Two confirms | Built, not run | — | Different by design: one dialog |
| 54 | Lock disabled when there is no prose | 400 from the server | Built, not run | — | — |
| 55 | Dictation in the Godric chat | Thumb button | Run | Me on iPhone (starts, shows recording, stops; no speech) | — |
| 56 | Dictation into the prose at the caret | Insert at the dictation point, never replace | Run | Andy on iPhone (short dictation, caret stayed in place) | — |
| 57 | Dictation into a chapter-length field | As above | Built, not run | — | — |
| 58 | Dictation ending unprompted loses nothing | As above | Built, not run | — | — |
| 59 | Dictation hides the keyboard, keeps the caret, keeps the keyboard away after stopping and after Save | No on-screen keyboard | Different | Run by Andy on iPhone | iPad-only behaviour for small screens |
| 60 | Return from the background re-reads the chapter | Re-read on open | Built, not run | — | — |
| 61 | Pull to refresh | n/a | Built, not run | — | iPad-only |
| 62 | Chapter actions as glass pills in the bottom bar (Add beat) | Buttons in the pane | Different | Run by Andy on iPad mini, iPhone upright and iPhone on its side | Design rule: contextual actions sit in the glass bar, same size as Ask Godric |
| 63 | The other pills: Save and Discard, Apply and Discard, Undo arrow | n/a | Built, not run | Not seen | — |
| 64 | Ask Godric shrinks to his sparkle on an upright phone | n/a | Different | Run by Andy on iPhone | Makes room for the action pill |
| 65 | Mic, Note and Notes pinned beside Chapters; icons only on a phone | Toolbar in the margin | Different | Run by Andy on iPhone | So they stay in view on a small screen |
| 66 | Docked Godric resizes by a drag handle (Creation and Ideation) | Fixed pane | Different | Run by Andy on iPad mini, portrait and landscape | Width remembered between visits |
| 67 | iPad mini layout: picker, chapter, beats, Godric docked, text editing | Desktop | Run | Me and Andy, portrait and landscape | — |
| 68 | iPhone width: chapter view, Godric sheet, Generate and Accept | n/a | Run | Me and Andy | — |
| 69 | iPhone on its side | n/a | Run | Andy | — |
| 70 | Dismissed references come back when Generate re-infers them | Same on the desktop (server behaviour) | Different | Seen by Andy on iPad mini | Known and deliberately unchanged here. A server question for the author; not changed in the iPad app |
| 71 | App 0.6.0, minimum server 0.55.0 | n/a | Run | Me: the app connects to server 0.55.0 | — |
| 72 | Locked chapter: beats read-only | Desktop hides "Add a beat at the end" and "Undo last draft" | Run | Me on iPhone 14 Pro, The House chapter 1 with a test beat added on dev | Add beat pill, move arrows, beat menu, Add reference and Propose references are hidden; Generate is greyed; each beat says "Chapter is locked. Unlock to change." |
| 73 | Locked chapter: other entry points | Same | Built, not run | Gated in the model (`requireUnlocked`) and the views, but no locked chapter had a draft, an Undo or a pending Godric change | Accept, Regenerate, Discard draft, Undo, Lock as draft one, Apply, reference chip menu |
| 74 | Unlock to change… / Lock again | Confirm with the server's warning, PUT proofread-lock {locked:false, accept:true}; "Lock again" the reverse | Run | Me on iPhone 14 Pro: warning shown, unlocked (server confirmed locked false), controls came back, Lock again re-locked | Not run on iPad mini. Locking again with unsaved edits is refused with "Save or discard your edits first." |
| 75 | 423 PROSE_LOCKED in words | Toast "This chapter is locked, so nothing was saved." | Built, not run | Server confirmed to answer 423 on prose-with-beats; the app text was not triggered | Prose save keeps its own message; every other beat or reference failure says "Chapter is locked. Unlock to change." and re-reads the chapter |

| 76 | Prose formatting: Bold, Italic | Cmd-B / Cmd-I; stored as `**bold**` and `*italic*`; drawn bold and italic | Run | Me on iPhone 14 Pro and iPad mini (Dev build, chapter 2517 of The Route): wrap, unwrap, bold on italic, no selection, from the top action bar with the keyboard up; focus and selection kept. Saved; `prose.raw` from GET differs from the text before only by the typed markers | Cmd-B / Cmd-I are wired but a hardware keyboard was not used. Markers are dimmed, not hidden; text is drawn styled by attributes only (balanced pairs inside one paragraph). Buttons are in the top bar beside the microphone, shown only while a prose segment is the active one; on a phone the Chapters label shrinks to its arrow to make room. Update: markers of a balanced span are now hidden (clear, 0.01pt font; string unchanged) and shown dimmed only while the caret or selection touches that span, restyled on selection change. Run on iPhone 14 Pro and seen on iPad mini: hidden on opening, revealed with the caret inside, Right-arrow across a hidden marker moves the caret one invisible character per press with no lost keystroke, typing and Backspace at a span edge work, Discard restored the original (hash unchanged). B pressed with only a caret mid-word inserts a `****` pair as specified. Selection wrap/unwrap through the hidden markers was not re-run in this build |
| 77 | Prose formatting: Scene break | Button; a paragraph of exactly `* * *`; drawn centred | Run | Me on iPhone and iPad mini: inserted between two paragraphs, caret left at the start of the next one, centred and letter-spaced in the editor; Save; GET shows `\n\n* * *\n\n` and nothing else changed | At the end of a segment before a beat card, and at the chapter end, was checked only by a standalone run of the same function |
| 78 | Formatting with unsaved-edits, Save, Discard | Autosave | Run | Me on iPhone and iPad mini: Unsaved edits appears; Save writes only the changed characters; reopening the chapter shows the styling again | Opening and saving an untouched paragraph set left every other byte of `prose.raw` identical (compared in full by script). Dictation insertion and the stale-save guard were not re-run with formatting; undo not exercised after a button press. Hidden-marker build: undo, dictation insertion and Save were not re-run |
| 79 | Desktop shows the app's formatting | Renders bold, italic and the scene-break divider | Built, not run | The stored form matches what the desktop splits on (`\n\n* * *\n\n`, index.html ~10236) | Not opened in the desktop on :3000 |

## Rows still not run

- 3. "Draft one — locked" text in an open chapter
- 5. Book menu with more than one book
- 7. Prune empty beats on leaving
- 9. Brief edit and save
- 12. Beat add "in the text" (paragraph stepper)
- 19. References: link a name to an existing entry
- 21. References: restore a dismissed name
- 23. Continuity block on a beat
- 27. Beat-change Discard
- 28. Beat-change card at iPhone width
- 30. Generation stop: codex gap, with dismiss and link
- 31. Generation stop: continuity
- 36. Discard a draft
- 37. Undo last draft
- 41. Add, delete, move, accept, undo, lock, generate refused while text is unsaved
- 42. First save of a session sends begin_session
- 44. Save refused: beats changed (BEATS_CHANGED)
- 45. Save refused: empty chapter (400)
- 50. Drafting note: clear and reopen
- 51. Drafting note: highlight in the text
- 52. Drafting note: "can't place"
- 53. Lock as draft one, with warning for open notes
- 54. Lock disabled when there is no prose
- 57. Dictation into a chapter-length field
- 58. Dictation ending unprompted loses nothing
- 60. Return from the background re-reads the chapter
- 61. Pull to refresh
- 63. The other pills: Save and Discard, Apply and Discard, Undo arrow
- 73. Locked chapter: Accept, Undo, Lock as draft one, Apply a Godric beat change, reference chips
- 75. 423 PROSE_LOCKED shown in words on beat and reference calls
- 79. Desktop shows the app's formatting

## Bug Hotel candidates

- Dictated words do not scroll the page to the caret.
- Drag reordering of beats (Move up/down only).
- Create or develop from a gap in World & Character, once W&C reaches the iPad.
- "Can't place" matching approximates the desktop's.
- A note cannot span two passages.
- Lock uses one dialog; the desktop uses two.
- Dismissed references return when Generate re-infers them: a server question, deliberately unchanged.
- Server, not client: on a locked chapter the dev server accepts insert-beat, beat delete and lock-draft (all returned 200). Only prose saves answer 423. The app now stops these client side, as the desktop does, but the routes themselves are unguarded.
- Opening a locked chapter flips a briefed chapter to Drafting (server side effect of GET chapter); the desktop does the same.
