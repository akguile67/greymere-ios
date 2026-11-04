# Codex panel exit checklist, iOS 0.9.0 (platform card 0.59.0)

*Against `docs/codex-parity-checklist-0.59.0.md` in the server repo and the author's decisions of 3 November 2026. Written from the build on 4 November 2026. "Seen" means the author ran it on the iPad mini and iPhone; "built" means it compiles and is installed but was not run.*

## Shipped and seen

| # | What | Notes |
|---|---|---|
| 1 | Browse by type, search by name and text, filter by Series and Book series, Recent | Portrait drill-down; landscape split with a draggable strip and full screen, both devices |
| 2 | Read an entry: portrait, Series, Book series, body with headings, bold, italic | |
| 3.1 | Edit name, aliases, body (typed or dictated), through review and Apply | Marked-up diff plus the formatted result; refused if the entry changed meanwhile |
| 3.3, 3.4 | Series (top level, several), Book series, Appears in (books) | An entry needs at least one Series |
| 3.5, 3.6 | New entry, delete entry with confirmation | New entries default to the Series being viewed |
| 4.2 | Make an image with Godric: prompt, edit, generate (cost confirmed), Use this image | About $0.04 a run |
| 4.4 | Standardise a location to its template | One entry at a time; lands in the editor with Undo |
| 5 | Find missing: scan a book's synopsis, Develop, Link, Dismiss, Put back, Clear | |
| 6.1 | Ask the Codex, with source chips | |
| 6.2 | Godric with the open entry as context; his drafted changes appear as a diff with Apply and Discard | |
| 6.3 | Dictation into the editor | |
| Sync | Devices follow each other within about 15 seconds while the panel is open | A polling stop-gap, see below |

## Built, not run by the author

- 3.1 body editing of headings in the editor (seen once, not all cases).
- 4.1 upload an image from Photos; 4.3 approve, reject and delete an image.
- Find missing: saving a developed entry (the form opened and was pre-filled).

## Not shipped

| What | Why |
|---|---|
| Camera as an image source | Needs a permission string and a camera picker; Photos only for now |
| Change an entry's type while editing | Type is chosen when the entry is created |
| Search by alias; Contains and "In:" chips for rooms inside buildings | Needs the server to send aliases and parent ids in the list |
| Server-side stale-edit guard | The app checks before writing; a second device saving in the same instant could still slip through |
| Live updates instead of the 15-second look | Needs the server to announce `codex.changed` |
| Archive controls, World map, tappable references, appears-in-chapters | Decided out (D4, D2); the map is being retired on the desktop |
| Standardise for characters and the batch Standardise | Bug Hotel #326 |

## Server work owed (brief: `server-brief-codex-list.md` in the notes folder)

1. Aliases and `parent_id` in `GET /api/codex`.
2. Optional `base_updated_at` guard on `PUT /api/codex/:id` (409 `{error:'stale', current}`).
3. Publish `codex.changed` after Codex writes.

The app tolerates all three being absent. The desktop Codex panel is untouched.

## Housekeeping done

- Throwaway prototype folder and target removed; `docs/codex-prototype-findings.md` and the screenshots stay as the record.
- Minimum server version raised to 0.59.0 (production is on 0.58.0, so the server release must go first).
