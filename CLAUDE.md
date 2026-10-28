# Greymere iOS — Claude Code entry point

The native iPhone and iPad app for Greymere (SwiftUI, iOS 26 minimum). A client
of the Greymere server, which lives in `~/Code/greymere` (GitHub
`akguile67/greymere`). This repo holds the app only; server work is done there.

- **Own version line.** The app is iOS X.Y.Z; the board carries the server
  version. Compatibility is a minimum-server-version check against
  `GET /api/instance`.
- **First release: iOS 0.1.0**, a read-only Home screen. The scope is ADR 0.50.0:
  `~/Code/greymere/docs/adrs/adr-0.50.0-ios-0-1-0-mobile-foundation-home-landing-screen.md`.
- **Builds happen on the MacBook Pro only** (Xcode, Team ID D25P46655T). Two
  bundle IDs, prod and pre-prod, distributed through TestFlight. Connection is
  over Tailscale.
- **One project per session.** Server changes (the Home aggregate endpoint, the
  version fields) belong in the Greymere repo and its release branch.
