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
- [ ] Code signing — needs a code-signing certificate

## Longer term / Ideas

- [x] Scrobble from local media players (VLC, foobar2000) — covered by generic SMTC mode when any SMTC-compatible player exposes a session; no dedicated plugin architecture for players that don't
- [ ] Last.fm friends' listening activity in the tray (currently only on the in-app Friends page)
- [ ] macOS companion app (using MusicKit / MediaPlayer APIs)

---

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
