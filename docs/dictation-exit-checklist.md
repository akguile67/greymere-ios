# Greymere Dictation on iOS — exit checklist for iOS 0.4.0

Captured **29 October 2026**, from ADR 0.53.0 ("Greymere Dictation", card 118, server release 0.53.0; the card
title wrongly says iOS 0.3.0, the app version is **0.4.0**). This is the fixed target for the iOS side. The desktop
side (hotkey, corrections screen) is in the ADR's Sprint 1 and Sprint 2 and is not repeated here.

Source: ADR 0.53.0 (Scope, Design, Sprint 2 DoD), `dictation-spike-decision-note.md`, and the app as at iOS 0.3.0
(`ChatInput` and `InertMicSlot` in `GodricChatView.swift`).

**The iOS app's part is small by design.** It captures microphone audio, streams it over Tailscale, shows what
comes back, tracks the author's edits to dictated text and reports them. The model, the spelling prompt, the
Codex name match and the correction map all live on the server. The app makes no AI call and holds no vocabulary.

**Dependencies that are not in this repo.** The server's dictation endpoint (session open, audio stream, pending
and fixed text, edit report) does not exist yet and its shape is decided in Sprint 1. Nothing here is built until
**Sprint 1's go/no-go is "go"**. On "no-go" this checklist is revisited with the ADR.

## A. Entry point: the thumb button

- [ ] A1. The mic slot in the chat input (inert since 0.3.0) becomes the dictation button. The slot's place in the layout does not move.
- [ ] A2. A tap starts dictation; a tap again stops it. (Hold-to-talk is not offered. ADR: "starts and stops".) The button shows three states: idle, listening, and unavailable.
- [ ] A3. The button is within thumb reach on iPhone: at the bottom edge, in the input row. On iPad it sits in the same row; the layout is not changed for iPad.
- [ ] A4. **Open point for the wireframe:** whether the button is also made larger than the other input controls while listening. Settled at wireframe approval (see wireframes, item 1).
- [ ] A5. The button is shown only where there is a text field to dictate into. In 0.4.0 that is the Godric chat input; no other text field exists in the app.
- [ ] A6. Dictation never starts by itself, and stops when the app goes to the background, the screen locks, or the author leaves the chat.

## B. Microphone permission

- [ ] B1. `NSMicrophoneUsageDescription` is set in `project.yml` for both targets, with a plain reason ("Greymere listens while you dictate; audio is sent to your own Greymere server and is not stored").
- [ ] B2. The permission prompt appears the first time the button is tapped, never at launch.
- [ ] B3. If permission is denied, the button shows its unavailable state and a tap explains how to turn the microphone on in Settings. Typing still works.
- [ ] B4. No speech-recognition permission is requested. The app does not use Apple's speech frameworks (ADR: Apple route out of scope).

## C. Audio capture and streaming

- [ ] C1. The app captures the microphone, resamples to **mono 16-bit PCM at 16 kHz**, and streams it to the server's dictation endpoint over the existing server connection (Tailscale, same host as the rest of the app).
- [ ] C2. The session opens with its **context** (Home chat; `bookId` when chat was opened from a book) so the server can build the spelling prompt. The app sends no vocabulary.
- [ ] C3. **Audio is not stored on the device.** Buffers are discarded as they are sent; nothing is written to disk.
- [ ] C4. The audio session is configured for recording while the chat is open and is released when dictation stops, so other audio on the phone is not held.
- [ ] C5. Interruptions (phone call, Siri, another app taking the microphone, headphones unplugged) end the session cleanly: pending text is kept as typed text, the button returns to idle.
- [ ] C6. Bluetooth and wired headset microphones work if iOS offers them; the app does not choose between microphones itself.

## D. Live text in the field

- [ ] D1. The server sends **pending** text (can still revise) about each second and **fixed** text at each pause. The app shows both in the field, in the chat input, at the cursor.
- [ ] D2. Pending text is styled differently from fixed text (the wireframes propose a lighter weight and a dotted underline). Fixed text looks like ordinary typed text.
- [ ] D3. When a segment is fixed, its text does not change. A word does not flip between pending and fixed (the server runs the same post-step on both, ADR).
- [ ] D4. Anything the author has typed before or after the dictated span is left alone. Dictation inserts at the cursor and only replaces its own pending span.
- [ ] D5. If the author types while dictating, the pending span is fixed as it stands and dictation continues after the typed text.
- [ ] D6. On stop, any pending text is fixed as it is, and the field becomes ordinary text. Nothing is sent to Godric until the author presses Send. Dictation never sends a message by itself.
- [ ] D7. The text the app shows is exactly what the server returned. No spelling, capitalisation or punctuation change is made on the device (verbatim guarantee, ADR).
- [ ] D8. The author's keyboard auto-correct and predictive text do not alter the dictated span while it is pending.

## E. Substitutions: marked, undoable

The server's post-step may replace a heard word with a name from the correction map or the Codex. The ADR requires
every such substitution to be marked in the field and undoable in one action.

- [ ] E1. The server marks each substitution in its reply (which span, the heard text, why). The app shows the substituted word with a visible mark (the wireframes propose a solid underline).
- [ ] E2. Tapping a marked word offers **Undo** (one action). Undo restores the heard text in the field and tells the server (counts against the row; adds a `keep` row where the match was the Codex's).
- [ ] E3. A marked word stays marked until the message is sent or the field is cleared.
- [ ] E4. The app never decides what is a substitution. It shows and reports what the server says.

## F. Learning from the author's edits

- [ ] F1. The app tracks the span it inserted. Only **fixed** text is tracked, never pending.
- [ ] F2. When the author edits inside a dictated span and stops (the field loses focus, or after a short quiet period; value set in Sprint 1 so desktop and phone agree), the app diffs the passage and reports word-level substitutions of up to four words either side to the server.
- [ ] F3. Pure insertions, pure deletions, punctuation-only changes and edits that rewrite most of the passage are not reported (that is writing, not fixing).
- [ ] F4. The report carries the context (book where there is one) so the server can scope the new row. The app does not choose the scope.
- [ ] F5. Editing after Send is not tracked; the message has left the field.
- [ ] F6. **There is no corrections review screen on iOS in this release.** Rows are reviewed, rescoped and deleted on the desktop. The app applies them (through the server) and reports edits.

## G. Server unreachable and errors

- [ ] G1. If the server cannot be reached when the button is tapped, the button shows **unavailable**, a short message says dictation needs the server and Tailscale, and typing still works. **There is no offline dictation.**
- [ ] G2. If the connection drops mid-session, the session ends; text received so far is kept (pending text becomes fixed), a note says dictation stopped, and the button returns to idle.
- [ ] G3. A server too old to have dictation: the app's minimum server version is raised to **0.53.0** in this release, so the Connect screen's existing refusal covers it. The dictation button is not shown against an older server.
- [ ] G4. Errors are shown in the same plain style as Godric errors (status chip, short message). They never lose typed text.
- [ ] G5. A dictation session is independent of a Godric turn: the button is disabled while a turn is running (the input is locked, as now) and enabled again when the reply lands.

## H. Privacy and no-AI

- [ ] H1. The app sends audio only to the Greymere server it is connected to. No third-party service, no analytics.
- [ ] H2. Audio is held in memory only as long as a window needs it, on the device and on the server.
- [ ] H3. The app calls no AI service during dictation. (ADR no-AI check: confirmed from logs for the whole stack.)

## I. Tests that need the device

- [ ] I1. **Real-microphone latency from the phone over Tailscale**: median, 95th percentile and worst case, from speech to text on screen, against the simulation's 0.65 s, 0.76 s and 2.6 s. Recorded in the release notes.
- [ ] I2. The spike script and the held-out script read aloud into the phone, scored against the 8-of-30 baseline (ADR test plan). Counted by the author.
- [ ] I3. A free-talk session longer than the spike's five minutes on the phone: no dropped passages, no loops.
- [ ] I4. A substitution made and undone; an edit made and learned; the same word dictated again and corrected automatically (check on iPhone, then on the desktop to see the same row).
- [ ] I5. Permission denied, server off, airplane mode, a phone call mid-session, headphones in and out.
- [ ] I6. The author uses it in a real session and says whether the live feel (text a second behind, revising as it settles) is acceptable on the phone.

## J. Versions and release

- [ ] J1. `MARKETING_VERSION` in `project.yml` is **0.4.0** for both targets. The project is regenerated with XcodeGen and committed.
- [ ] J2. The app's minimum server version is **0.53.0**. (It was 0.52.0.)
- [ ] J3. The server's `/api/instance` reports 0.53.0 and the Connect screen shows it.
- [ ] J4. Builds and runs on the iPhone 14 Pro (real), iPad mini 7 and iPad Pro 13-inch, portrait and landscape on iPad. Both bundle IDs install through TestFlight.

## K. Not in 0.4.0 (to Bug Hotel)

- Dictation corrections review screen on iOS (desktop only).
- Any LLM rewriting or interpretation. Not now, and not as an option.
- Apple's on-device speech route and Apple custom pronunciations.
- Dictation outside Greymere (system keyboard) and any other text field than the chat input (there is none yet; new panels bring their own fields).
- Offline dictation when the server is not reachable.
- Multi-speaker support; adapting the model to the author's voice.
- Retiring the old AI-interpreting dictation tool and its dead mic button (desktop; ADR open point).
- A hotkey on iPad with a hardware keyboard. The thumb button is the entry point; a key command is a later item.
- Streaming Godric's replies and per-message cost (still the 0.3.0 Bug Hotel items).
