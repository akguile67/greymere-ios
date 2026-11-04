# Release iOS 0.9.0: the Codex panel

*ADR 0.59.0 (platform card 0.59.0; iOS 0.8.0 is skipped on purpose). Written from the build, 4 November 2026. Needs server 0.59.0 (the app refuses an older one). Installed on the iPhone 14 Pro and iPad mini as Greymere Dev and as the pre-production app; checked on pre-production on 4 November. Server 0.59.0 is on production.*

## What it does

- **The Codex on your iPad mini and iPhone.** Browse by type, or search by name and text. Filter by Series (Crime Fiction, Historical Fiction, Greymere horror) and Book series. Recent keeps your last entries. Landscape shows the menu beside the entry with a draggable strip and a full-screen button; portrait drills down.
- **Edit, with a review.** Change an entry's name, aliases, body (typed or dictated), Series, Book series and the books it appears in. Bold and italic show as bold and italic. Review shows the words that changed and how the body will read; nothing is written until Apply, and Apply is refused if the entry changed meanwhile.
- **New entry and delete.** New entries go into the Series you are viewing.
- **Images.** Add one from Photos, approve, reject or delete it, or have Godric write a prompt and make one (about $0.04, confirmed first, kept only when you press Use this image). Lists show each entry's image as a thumbnail.
- **Standardise** a location to its template.
- **Find missing.** Scan a book's synopsis, then Develop an item into a new entry, Link it to an existing one, Dismiss it or Put it back.
- **Godric.** The Ask Godric pill opens a chat that knows which entry is open; a change he drafts shows as a diff you Apply or Discard. **Ask** on the Codex home answers a question across the whole Codex and names its sources.

## Differences from the plan

- The navigation was built and approved on a throwaway prototype first (`docs/codex-prototype-findings.md`).
- Devices follow each other at once through server 0.59.0's `codex.changed` notice, with a 15-second look as a fallback.

## Not in this release

Camera as an image source, changing an entry's type, the batch Standardise (Bug Hotel #326). See `docs/codex-exit-checklist.md`.

## Not tested

Search by alias and the room chips on a device; the production iOS build.
