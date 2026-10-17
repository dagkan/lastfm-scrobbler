# Roadmap

## v1.0.0 — Current Release

- [x] Apple Music (Windows Store) scrobbling via SMTC API
- [x] Album name resolution via Last.fm `track.getInfo`
- [x] Configurable scrobble threshold (% and max seconds)
- [x] Track normalization with regex rules (Deluxe Edition, Remastered, etc.)
- [x] Dark UI with sidebar navigation (Monitor, Account, Scrobbling, Normalization)
- [x] System tray integration
- [x] Scrobble history (local SQLite)
- [x] Optional edit-before-scrobble dialog
- [x] Windows startup option

## v1.1.0 — Polish

- [x] Album art display in the monitor window
- [x] Windows 11 toast notifications with album art (best-effort — falls back to the classic balloon tip if toast registration fails on a given machine)
- [x] Scrobble history browser (searchable list of past scrobbles)
- [x] Retry queue for failed scrobbles (offline support)
- [x] Tray icon changes to reflect current state (playing, idle, error)

## v1.2.0 — Multi-player support

- [ ] iTunes / Apple Music (legacy) support — app-id string match exists, but unverified against an actual legacy iTunes install
- [x] Spotify support via SMTC
- [x] Any SMTC-compatible player (generic mode)
- [x] Per-player normalization rules

## v1.3.0 — Power features

- [x] Love/unlove track from tray menu
- [ ] Tag-based normalization (not just regex) — no tag/genre data source is wired in yet
- [x] Import/export normalization rules
- [x] Manual scrobble entry

## v2.0.0 — Distribution

- [ ] MSIX packaging for Microsoft Store distribution — needs a Store account
- [x] Auto-updater
- [ ] Code signing — needs a code-signing certificate. Now a concrete problem, not a nice-to-have: Windows 11 Smart App Control blocked an unsigned installer during the 1.2.22 beta test ("Error 4551: An Application Control policy has blocked this file"). Until then: always build with the stable Inno Setup 6 loader (the 7.0 preview was the trigger). Options: OV cert via SignPath (free for OSS) or Azure Trusted Signing.

## Longer term / Ideas

- [x] Scrobble from local media players (VLC, foobar2000) — covered by generic SMTC mode when any SMTC-compatible player exposes a session; no dedicated plugin architecture for players that don't
- [ ] Last.fm friends' listening activity in the tray (currently only on the in-app Friends page)
- [~] macOS companion app — SwiftUI menu-bar port in `macos/`, feature-complete but never compiled on a Mac yet. Plan and hand-off: [`macos/BRIEF.md`](macos/BRIEF.md)

---

## v1.2.22 — shipped 2026-10-17

- [x] Crash fixes from telemetry: monotonic listen-time clock (456/463 reports), STA UI thread (clipboard / dialogs)
- [x] Vector title-bar + sidebar icons, GitHub / Sponsor / Buy me a coffee buttons, rounded corners on Win11
- [x] Release notes in the update dialog; Version History tolerant of string `notes`
- [x] Opt-in global hotkeys (AltGr collision), opt-out telemetry re-implemented (1.2.20/1.2.21 sources were lost)
- [x] Side-by-side **beta channel**: `build.ps1 -Beta` → `/lastfm-scrobbler/beta/`, own AppId / folder / mutex / Run key
- [x] Layout fixes at the 900 px minimum width; Friends/About/Settings strings localized (7 languages)

### Open after 1.2.22
- [ ] Code signing (see v2.0.0) — the single biggest install-time risk left
- [ ] Proxy host stays `proxy.lastfm.spacechild.dev` for now; a move needs a release pointing at the new host first, old host kept as alias ≥ 6 months
- [ ] Re-uploading an installer under an existing filename can be served stale from the Cloudflare edge — always bump the version instead
- [ ] Crash reporter only covers WinForms `ThreadException` / `UnhandledException`; native crashes (e.g. in WinRT SMTC) are invisible
- [ ] `installer/versions.json` is the source of truth for the changelog — keep it committed; `build.ps1` prefers it over R2

## Pending / Backlog

### About Page
- [x] App name, version shown; no build-date field
- [x] GitHub + GitHub Sponsors buttons (GitHub button styling), Buy Me a Coffee kept for people without a GitHub account
- [x] GitHub link (`github.com/dagkan/lastfm-scrobbler`), changelog link (Version History)
- [x] App description (one paragraph)

### Better Navigation & Menu Structure
- [x] Account page replaced by a persistent sidebar ProfileCard (avatar, scrobble count, login/logout)
- [x] About added as a dedicated nav item
- [x] Sidebar grouping: Monitor | History | Stats | Friends | Scrobbling | Normalization | About

### Richer Account Page
- [x] Profile picture, total scrobble count shown via `user.getInfo`
- [ ] "Member since" (registered date) not fetched/shown
- [ ] Auto-show login prompt on first run when no session is stored (currently opens the Monitor page, where the ProfileCard's login button is visible but not auto-triggered)

### Custom Domain for Updates
- Solved functionally via the `proxy.lastfm.spacechild.dev` Cloudflare Worker (avoids the blocked `r2.dev` domain). The hostname is baked into every installed copy (API proxy + update manifest), so it must stay reachable — moving it means shipping a release that points at the new host first and keeping the old one alive as an alias until the install base has rolled over.

### Friends page redesign
- [x] Grid of avatar cards (avatar + username + last scrobbled track + relative time)
- [x] Click an avatar → open their last.fm profile in browser
- [x] "♥ now playing" indicator for friends currently listening
- [x] Avatars cached to disk (`avatar_cache/`) instead of refetched on every page open
