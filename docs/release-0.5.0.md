# Release iOS 0.5.0 — Ideation panel, the glass bar, and conversations you switch between

*ADR 0.54.0. Written from the build, 1 November 2026. Needs server 0.54.0 (the app refuses an older one). Live on production, pre-production and dev; installed on the iPhone 14 Pro, iPad mini and iPad Pro.*

## What it does

- **A floating glass bar on every screen:** Home, Ask Godric, and Panels, which raises a tray of the workflow stages (Planning to Review). Only Ideation is turned on; the rest are dashed. No back-office panels.
- **Settings gear at the top right** with About (iOS and server versions). The purple environment band is gone; pre-production and dev builds show a small tag beside the title.
- **Ideation panel:** the book's one synopsis (read, edit by hand, Lock), a book chip to change book, and Godric as a sheet over it (docked beside it on an iPad).
- **Godric drafts, you apply.** He never changes the synopsis. A change he drafts appears as a marked-up card (red struck-through words go, green words arrive, long unchanged stretches folded), the bottom bar shows only **Apply drafted change** and **Discard**, and a draft that removes more than a tenth of the synopsis carries a red warning. Hand edits are version-checked: if the laptop changed the synopsis meanwhile, you choose Keep mine, Take theirs or Copy mine, take theirs.
- **Conversations you switch between:** History lists only conversations you used. Continue reopens a conversation from the same panel (same book, for Ideation) and parks the one you were in; one from elsewhere asks whether to start a new conversation from it (default) or add it to the current one. New starts a blank conversation. Back (while reading a past conversation) returns to the one you were in. The conversation in use is marked "current".
- **No Refresh button.** To draft a synopsis, ask Godric ("update the synopsis please", "propose a draft").

## Differences from the plan

- Server 0.54.0 was needed after all (single synopsis per book, switching, propose-then-apply, truncation guard); see its release notes and ADR addenda 1 to 3.
- Pulling the screen up to raise the tray, and bold and italic buttons in the synopsis editor, are not built.
- Refresh was built, then hidden: a full rewrite hit the model's output limit and drafted a synopsis that deleted 1,758 words.

## Not tested

- Lock (it changes plan state) and a real first synopsis for a new book were not exercised on the app.
- iPad Pro and iPad mini were checked on the simulators; the real iPads were installed but not opened by me.
- The old web app (PWA) has no Apply button; Ideation should not be used there.
