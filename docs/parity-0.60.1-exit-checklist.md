# Parity with server 0.60.1: exit checklist, iOS 0.11.0

*Against `docs/ios-handoff-0.60.1.md`. Written 6 November 2026. "Built" means it compiles and is installed on the iPad mini (A20 Pro) as Greymere Pre-prod and Greymere Dev. "Seen" is filled in only after the author runs it on the iPad mini, then the iPhone 14 Pro. Seen on both on 6 November 2026 (items 1 to 4; the older-server refusal was not run).*

| # | Check | iPad mini | iPhone 14 Pro |
|---|---|---|---|
| 1 | Home: The Route's drafting item reads "3 created today, target of 2 reached" in bold and is ticked (Pre-prod; server returns this today) | Seen | Seen |
| 1b | Lock another chapter on the desktop, pull to refresh: the line moves | Seen | Seen |
| 1c | An item without progress (any other phase, or another day) draws as before | Seen | Seen |
| 2 | Structure: tap the triangle on a chapter card: the sheet lists gaps with Link, Create and Not required | Seen | Seen |
| 2b | Resolve one gap each way; the card's triangle updates; the desktop shows the same; a desktop dismissal is gone on the phone | Seen | Seen |
| 2c | Open card: the "Codex gaps" line opens the same sheet | Seen | Seen |
| 2d | Creation chapter list: the triangle opens the sheet | Seen | Seen |
| 2e | A gap already resolved elsewhere: the sheet says so and refreshes (409) | Seen | Seen |
| 3 | Creation: ask Godric to draft a missing codex entry; the diff card appears; Apply; entry is in the Codex | Seen | Seen |
| 3b | Apply the same card again / after a server restart: "Expired or already dealt with", no error | Seen | Seen |
| 3c | Ask for the next beat with none open: the empty beat card appears | Seen | Seen |
| 3d | Beat card and codex card in one reply: both shown | Seen | Seen |
| 4 | Brief editor, and a Godric-drafted beat not yet applied (asks before leaving; added after the author lost one): edit, tap Chapters: asked first; switch panel and return: edits still there | Seen | Seen |
| 5 | Connecting to a server older than 0.60.1 is refused | Built, not run | Built, not run |

## Not done in this release
- Server-side `GET /api/godric/claim-checks` check (handoff item 4) needs a few chats on the device first.
- Codex: no per-chapter gap list exists in iOS Codex, so nothing was added there.
