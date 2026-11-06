# Release iOS 0.11.0: parity with server 0.60.1

*Server handoff: `docs/ios-handoff-0.60.1.md` in the server repo. Written from the build, 6 November 2026. Needs server 0.60.1 (the app refuses an older one). Installed on the iPad mini (A20 Pro) and iPhone 14 Pro as Greymere Pre-prod and Greymere Dev, and checked there by the author (`docs/parity-0.60.1-exit-checklist.md`). Not installed as the production app.*

## What it does

- **Home: the drafting progress line.** On today's Home card, the drafting item shows the server's own line in bold under the book ("3 created today, target of 2 reached") and the item is ticked when the server says the target is met. The text is never worked out in the app. It reads again when Home opens and on pull-to-refresh (a chapter lock publishes no live notice yet, so it does not move by itself).
- **Codex gaps from the triangle.** Tap the warning triangle on a chapter card, in Structure or in Creation's chapter list (or the "Codex gaps" line on an open Structure card), and a sheet lists that chapter's gaps. For each: **Link to this entry** (the suggestions; shown first when the server says link comes first), **Create entry** as Character, Place or Object (a stub marked *needs development*; develop it with Godric afterwards), and **Not required**. The card behind it redraws. If the gap was already dealt with elsewhere, the sheet says so and shows what is left.
- **Creation: Godric's codex draft.** When Godric drafts a codex entry in a chapter conversation it appears in the chat as the same diff with Apply and Discard that Structure uses. A beat change and a codex draft can arrive together. If Apply finds the draft expired (the server was restarted, or it was already applied), the card says "Expired or already dealt with"; it is not shown as an error. When Godric opens an empty beat, the chapter is read again so the empty card appears.
- **Unsaved brief edits are no longer lost.** In the Creation brief editor, the Chapters button asks first when the brief has unsaved changes (Save brief and leave, Discard and leave, Keep editing). Switching to another panel cannot ask, so the chapter is left open as it was and the edits are there when you come back.

## Differences from the handoff

- iOS Codex shows **no per-chapter gap list**: its Find missing is the book-level list with its own states, a different thing. So the sheet opens from the triangle in Structure and in Creation's chapter list only, and no new surface was added in Codex.
- The codex draft card is drawn in the Godric chat (the shared bubble), not on the chapter page as the beat card is.

## Not in this release

A live push for the Home progress line (a one-line server change, `events.publishSoon` after the chapter lock). Still as in 0.10.0: act synopsis editing, Validate, History and New chat for the Structure thread.
