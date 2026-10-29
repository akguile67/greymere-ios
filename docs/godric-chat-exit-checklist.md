# Desktop Godric panel — exit checklist for iOS 0.3.0

Captured **29 October 2026**, the day card 0.52.0 started (ADR 0.52.0, "Parity
rule"). This is the fixed target: later desktop changes become parity items for a
later card, not changes to this list.

Source: the desktop Godric panel (`public/index.html`, `godricSend`,
`loadActiveConversation`) and the server in `~/Code/greymere/src/godric.js` and
`server.js` (`/api/godric/*`), as at server 0.51.0. No new endpoints and no
server change.

**Two findings that differ from the ADR text** (decided with the author on
29 Oct 2026: parity as built, ADR gets an addendum, the gaps go to Bug Hotel):

1. **The desktop does not stream.** `POST /api/godric/chat` returns one JSON
   object when the whole turn (including tool calls) is finished. The panel shows
   a "Thinking…" status and a three-dot typing bubble meanwhile. The app matches
   that. Token streaming is a Bug Hotel item (needs a server endpoint).
2. **The desktop panel shows no cost per message.** Cost appears per turn only in
   Ideation, which is not in this release. The app shows none either. Cost
   visibility in chat is a Bug Hotel item (needs the server to return it).

"Writes" here: Godric's own tools act on the server (reminders, Bug Hotel,
backlog, etc.) exactly as from the desktop. What the **app** never does is edit
data itself, apart from the chat messages.

## A. Conversation lifecycle

- [ ] A1. Opening the chat calls `POST /api/godric/conversation` with `{context, bookId?}` and shows the returned `messages`: the panel's active thread, or a new one seeded with Godric's opening message.
- [ ] A2. Each panel keeps its own thread. Leaving and coming back restores it (`context` is the panel key; the app has one panel to start with, `home`).
- [ ] A3. A thread idle past the server's expiry is archived and a new one opens; the app just shows what the server returns.
- [ ] A4. **New chat** button: `POST /api/godric/conversation/new` archives this panel's thread and shows the fresh one with its opening message.
- [ ] A5. **History**: list from `GET /api/godric/conversations` (title, summary, panel, when). Tapping one opens it **read-only** via `GET /api/godric/conversation/:id` with a banner "Viewing a past conversation" and a way back. Input is disabled while viewing.
- [ ] A6. **Continue** a past conversation (`POST /api/godric/conversation/continue`, `{key, context, bookId}`): same panel reopens it; otherwise its transcript is carried into this panel's thread.
- [ ] A7. Opening message and `temporal` (working day, next working day) come from the server; the app shows the message and uses `temporal` for the quick actions.

## B. Sending and receiving

- [ ] B1. Send: `POST /api/godric/chat` with `{context, message, bookId?}`. Not sent: `portfolio` (server builds the live one), `centrePanelSnapshot`, `contentContext`, `coverBriefContext`, `observationContext`, `codexPanelContext` (those belong to desktop panels that are not on the device).
- [ ] B2. The author's message appears at once (optimistic), the status reads **Thinking…** with the three-dot bubble, and the input is locked while a turn runs (`g_busy`).
- [ ] B3. The reply (`text`) appears whole when the server returns, in a Godric bubble with the time (HH:mm, local). **No token streaming** (see finding 1).
- [ ] B4. Reply text renders bold (`**x**`) and line breaks, as the panel's `markdownishToHtml` does; nothing else.
- [ ] B5. One turn at a time per conversation: a 409 from the server ("still working on your last message…") is shown as the error bubble, and the message can be sent again.
- [ ] B6. Errors: HTTP error shows "Godric error <status> — <first 200 chars>"; network failure shows "Could not reach Godric — …"; status turns **Offline**. The user turn is kept (the server saves it first).
- [ ] B7. Status chip: **Ready** / **Thinking…** / **Offline**.
- [ ] B8. Sending while viewing history is refused (input disabled).
- [ ] B9. Empty or whitespace messages are not sent.

## C. Quick actions

- [ ] C1. Under a thread with no author turn yet, the panel offers suggestion buttons for the panel (`G_QUICK_BY_CONTEXT[home]`, copied word for word at build time from the desktop source). Tapping one sends it.
- [ ] C2. On a non-working day the Home set is the "off" set with the next working day substituted (`G_GREET_QUICK_DASHBOARD_OFF`, from `temporal`).
- [ ] C3. They disappear once the author has sent a message.

## D. Per-panel context

- [ ] D1. The thread the app opens is the one for the panel it was opened from: `context` is sent on every call. In this release the app has the Home context only.
- [ ] D2. A focused book: when chat is opened from a book, `bookId` is sent on open and on every turn, and the book-switch note is appended with `POST /api/godric/book-switch` `{screen, bookId, bookTitle}` when the open book changes (server dedupes).
- [ ] D3. Godric reads the live portfolio on every turn (server side); the app sends no snapshot.
- [ ] D4. Context-shift (`/api/godric/context-shift`, no API call) is sent when the app moves to a different panel's context. Only relevant once a second panel exists; not exercised in 0.3.0.

## E. Cross-panel memory

- [ ] E1. The app keeps no memory of its own. Studio-wide memory is read by the server into every turn, and the post-turn sweep stores new decisions and commitments. Nothing is sent from the app for this.
- [ ] E2. Check: a fact told to Godric on the laptop is used by Godric in the app, and the reverse (tested on dev with a throwaway fact, then retired from Configurator → Godric → Memory).
- [ ] E3. Viewing or editing the Memory store is a Configurator feature and **not in 0.3.0**.

## F. Proposals and drafts

Godric can return `pending_codex_change`, `pending_content_draft`,
`pending_cover_brief_change` and `pending_cover_brief_export`; the desktop shows
Apply / Discard cards.

- [ ] F1. The reply text always shows. A turn that returns a proposal shows a plain note under the bubble: "Godric drafted a change. Review and apply it on the desktop." No Apply, no Discard, no diff on the phone.
- [ ] F2. Applying or discarding codex proposals (`/api/godric/codex-proposal/*`) is **not in 0.3.0** (Bug Hotel). Proposals the app leaves alone stay pending on the server, as on the desktop when ignored.

## G. Input component and mic slot

- [ ] G1. One reusable input component: multi-line text field, Send button, and a **mic slot** in its structure and layout.
- [ ] G2. The mic control is present but inert and visibly disabled; nothing sits behind it (no permission prompts, no audio code). 0.53.0 fills the slot.
- [ ] G3. Send is disabled while a turn runs, while history is open, or when the field is empty.

## H. Not in 0.3.0 (to Bug Hotel)

- Token streaming; cost per message (findings 1 and 2).
- Applying or discarding proposals; content-draft routing to the editor.
- Persona, Memory and Layers screens (Configurator).
- Centre-panel snapshot and the other panel-specific context fields.
- Any pane; offline Godric; dictation.
- Chain (series) selector: the desktop filters Godric by the active series; the app follows whatever the server has active and has no selector.

## I. Devices

- [ ] I1. iPhone 14 Pro (real; the ADR says iPhone 14 Plus, same width class), iPad mini 7 and iPad Pro 13-inch, portrait and landscape on iPad.
