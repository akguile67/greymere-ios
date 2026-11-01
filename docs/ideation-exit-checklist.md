# Desktop Ideation panel — exit checklist for iOS 0.5.0

Captured **1 November 2026**, the day card 0.54.0 started (ADR 0.54.0, "Definition
of Done"). This is the fixed target: later desktop changes become parity items for
a later card, not changes to this list.

Source: the desktop Ideation panel (`public/index.html`: `ideationLoadConversation`,
`ideationRenderSynopsis`, `setIdeationTopActions`, `ideationDispatchMessage`,
`ideationRefreshSynopsis`, `ideationLockSynopsis`, `ideationDoneEdit`) and the server
in `~/Code/greymere/src/ideation.js` and `server.js` (`/api/ideation/*`), as at
server 0.53.0. **No server change.** The audit is in ADR 0.54.0.

Items marked **(deferred)** are desktop behaviours the ADR puts out of scope; each is
logged to Bug Hotel rather than built.

## 0. Menu shell (new in 0.5.0, decided 1 Nov 2026)

- [ ] 0.1. A floating glass bar on every screen: Home, the Ask Godric pill, Panels. The tint is the one theme token.
- [ ] 0.2. The Panels button raises a tray (pulling the screen up, as in Music, is not built in 0.5.0) of the workflow stages only (Planning to Review, in the desktop rail's order). Only panels the app has are tappable; the rest are dashed. No back-office panels.
- [ ] 0.3. A gear at the top right drops a menu holding About with the iOS and server versions. Nothing else yet.
- [ ] 0.4. The purple environment band is gone. A pre-prod or dev build shows a small tag beside the title; production shows none.
- [ ] 0.5. A book chip on book panels drops a list of books in work and is remembered across panels.

## A. Opening

- [ ] A1. Entered by choosing Ideation in the tray (or changing book in the chip). Calling `GET /api/ideation/books/:bookId/conversation` is the only thing that creates the conversation and rolls the "Idea development" plan step back to in progress. Never called to preview or prefetch.
- [ ] A2. Shows the book title, the methodology name (`conversation.methodology_codex_entry_id`, name from `GET /api/codex/:id`; empty when none) and a status line: "New conversation — start the debate." with no chat turns, otherwise "N turns · last active …".
- [ ] A3. The synopsis pane shows `conversation.synopsis_draft`. When the book has a saved synopsis (`has_saved_synopsis`) the title reads "Saved synopsis"; otherwise "Developing synopsis".
- [ ] A4. The thread shows the `opening` and `chat` messages (`text_only`) under a note "Ideation conversation — against {methodology}" (or "no methodology bound"). Other message kinds are not shown.
- [ ] A5. Opening an edit is never carried over to another book.
- [ ] A6. The book chip changes book, as the desktop's `g-id-book-select` does (books in work: status not `idea`, not closed unless republishing, not released; the Home payload's fields decide, any gap is logged).

## B. Synopsis pane (read)

- [ ] B1. Empty state text: the synopsis builds as decisions are made; say "capture what we now know" or use Refresh; Lock when usable. Meta line: "Empty — nothing captured yet".
- [ ] B2. With text: the markdown is rendered (headings, bold, italic, lists as the desktop's `codexMarkdownToHtml`), with a word count. When updating a saved synopsis the meta also shows "Editing saved synopsis".
- [ ] B3. Lock and Edit are unavailable while the synopsis is empty; Refresh is always available.

## C. Talking to Godric

- [ ] C00. A New conversation button beside History ends the book's Ideation conversation (it stays in History) and opens a blank one with Godric's opening; the synopsis is carried over unchanged (`POST …/end`, then `GET …/conversation`, then the draft is restored if the new conversation started without it).
- [ ] C0. Ask Godric raises the book's Ideation thread as a sheet over the synopsis (iPad: docked beside it). Closing it shows the synopsis; a mark says when Godric changed it.
- [ ] C1. A message goes to `POST /api/ideation/books/:bookId/messages` `{text, source_pane}`. The author's message appears at once; status "Thinking…" with the typing bubble; input locked while a turn runs.
- [ ] C2. The reply appears whole (the endpoint does not stream). No cost line in the thread (as on the desktop).
- [ ] C3. When the reply carries `synopsis_updated: true`, the synopsis pane is re-read from `GET …/conversation` and repainted, unless an edit is open (then it is left alone).
- [ ] C4. An error shows in the thread as "Godric error {status} — {body}" or "Network error …"; the input unlocks.
- [ ] C5. The 0.4.0 input and dictation work in this thread unchanged.
- [ ] C6. Suggestion buttons are not shown (as in 0.3.0).

## D. Refresh phrases and Refresh

- [ ] D1. A message that is *wholly* one of these phrases (plus filler words `please now again just ok okay thanks thank you go ahead and then so right`) fires the refresh instead of a chat turn: "capture what we now know", "capture that", "capture this", "capture what we know", "refresh the synopsis", "update the synopsis", "rewrite the synopsis", "write that down", "write this down". The same list and the same whole-instruction rule as the desktop.
- [ ] D2. A phrase inside a longer sentence ("Godric, update the synopsis with the new ending") is sent to Godric as a normal message.
- [ ] D3. The desktop also sends what is left of the message (only filler such as "please") to Godric as a chat turn. The app does not: a pure command only refreshes, and the thread shows a note "Refreshing the synopsis from the conversation…" (the sheet may cover the pane).
- [ ] D4. The Refresh action calls `POST …/refresh-synopsis`, shows "Refreshing…", repaints with `synopsis`, and shows the returned `cost_usd` once it finishes (the ADR adds this to the desktop's behaviour).
- [ ] D5. `discarded: true` shows "Refresh dropped: the synopsis changed while it ran, so it was left as it is. Refresh again if you still want it." and leaves the pane as it was.
- [ ] D6. A failed refresh shows "Refresh failed: {status} …" and leaves the pane as it was.

## E. Editing by hand

- [ ] E1. Edit opens the raw markdown text for editing (bold and italic are typed as `**` and `*`; the desktop's B and I buttons are not built, logged to Bug Hotel). The text it started from is remembered. Done editing / Cancel replace the pane actions.
- [ ] E2. Cancel discards the changes with no server call.
- [ ] E3. Done with no change closes with no server call.
- [ ] E4. Done with a change calls `PATCH …/synopsis-draft` `{text}`; on success the pane shows the new text; on failure it shows "Save failed: {status} …" and stays in edit mode with the text kept.
- [ ] E5. **Conflict guard.** The PATCH carries the version the edit started from (`base_version`, server 0.54.0). A 409 means the synopsis moved on: nothing is overwritten and the author chooses *Keep mine*, *Take theirs*, or *Copy mine and take theirs*. Against an older server the app re-reads and compares the text instead.
- [ ] E5a. One synopsis per book: the app shows and edits the book's synopsis, never a conversation's. Switching, New and Continue never change it; only Refresh, the update phrases, Done editing, Godric's edit on request, and Lock do.
- [ ] E6. A save writes through to the saved synopsis when one exists (server behaviour); the app does not call `save-synopsis`.

## F. Lock

- [ ] F1. Lock synopsis calls `POST …/lock-synopsis`.
- [ ] F2. When the book has no saved synopsis, the author confirms first, in words matching the desktop: it is saved to the codex as the synopsis Godric reads, ideation is marked complete, the book moves on to the Codex update. When updating a saved synopsis there is no confirmation.
- [ ] F3. Success shows "Synopsis locked · Godric reads this version · the book is in the Codex update", or, when `already` is true, "Synopsis locked · already the working copy, nothing further to change"; the pane switches to the saved framing.
- [ ] F4. Failure shows "Lock failed: {status} …" (for example an empty synopsis) and changes nothing.
- [ ] F5. The portfolio is refreshed after a lock so Home shows the new state. The hand-off to the Codex panel with Find missing open is a desktop step in this release; the app returns to the book.

## G. History and Continue

- [ ] G1. The History sheet lists conversations from `GET /api/godric/conversations` (Home and Ideation together; keys `g-N`, `i-N`) with title, summary, panel and when.
- [ ] G1a. The conversation in use is marked "current"; tapping it returns to the live thread (it is not a past conversation, and Continue is not offered for it).
- [ ] G1b. Closing Godric leaves any past conversation being read, so he reopens on the live thread.
- [ ] G2. Tapping one opens it read-only with the banner "Viewing a past conversation", Back, and Continue. Input is disabled while viewing.
- [ ] G3. **Continue** calls `POST /api/godric/conversation/continue` `{key, context, bookId}` and reads `mode`. *(Server 0.54.0.)*
- [ ] G4. A conversation from the same panel (for Ideation: the same book) **reopens** as itself; the one the author was in is parked in History. The note reads "Reopened". The synopsis is unchanged.
- [ ] G4a. A conversation from another panel or book asks: *Start a new conversation from this* (default, `into: "new"`) or *Add to the current conversation*. The note reads "Brought into a new conversation" or "Brought into this chat".
- [ ] G4b. **Back** appears only while reading a past conversation and returns to the conversation the author was in ("Back to current conversation").
- [ ] G4c. History lists only conversations with at least one user turn (server filter).
- [ ] G5. History and Continue live in the Godric sheet, from Home (`home`) and from the Ideation thread (`ideation` with the book).
- [ ] G6. A refusal or failure (for example "That is this conversation already", "That conversation has nothing to carry in") shows the server's message in place, and the past conversation stays on screen. Nothing is discarded silently.

## H. Deferred (logged to Bug Hotel, not built)

- [ ] H0. Pull the screen up to raise the tray; the desktop's B and I buttons in the synopsis editor; the pushed Seed screen has no glass bar.

- [ ] H1. Back-office panels in the tray; Settings beyond About (waits for the Configurator panel); Book Details shortcuts into panels.
- [ ] H2. Linked research strip (`GET /api/books/:id/research`): read-only list of papers, collapsible.
- [ ] H3. Server version check on synopsis saves.
- [ ] H4. Hand-off to the Codex panel after Lock.
- [ ] H5. Apply and Discard for drafted codex changes; streaming; per-message cost.

## I. Devices and layout

- [ ] I1. iPhone 14 Pro (real), iPad mini (A17 Pro) and iPad Pro 13-inch (M5) simulators. Size classes, no per-device code paths.
- [ ] I2. iPhone: the synopsis is the screen and Godric is a sheet. iPad: Godric docked beside the synopsis.
- [ ] I3. Wireframes approved before any SwiftUI is written.
