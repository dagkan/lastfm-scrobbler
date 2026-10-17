# macOS port — brief & plan

Hand-off for continuing the work from a Mac. Everything below reflects the state of `macos/` on `main` as of 2026-10-17 (commit `6d266d8` or later).

## 1. Where things stand

| Area | State |
|---|---|
| App shell | SwiftUI + AppKit menu-bar app (`LSUIElement`), `NavigationSplitView` main window, 7 pages mirroring Windows (Monitor, History, Stats, Friends, Settings, Normalization, About) |
| Media source | `DistributedNotificationCenter` → `com.apple.Music.playerInfo` (Apple Music only, no Automation/Accessibility prompt) |
| Scrobble engine | Rewritten 2026-10-17 to the Windows model: accumulated listen time on `ProcessInfo.systemUptime`, Paused freezes the clock, Stopped is debounced 1.5 s, replay after a scrobble is a new listen, threshold = max(min, min(pct·duration, max)) capped 5 s before track end |
| Backend | Same Cloudflare Worker as Windows (`proxy.lastfm.spacechild.dev`): Last.fm proxy (`LastFmClient`), telemetry (`Telemetry.swift`), update manifests (`UpdateChecker`) |
| Updates | `/lastfm-scrobbler/macos/latest.json` + `versions.json` (already proxied by the worker, no worker change). Download → SHA-256 verify → open DMG; **not** an in-place replace yet |
| Persistence | SQLite via `SQLite3` C API in `~/Library/Application Support/LastFmScrobbler/lastfm.db` — same schema keys as Windows where it matters (`settings`, `normalization_rules`, `scrobble_history`, `pending_scrobbles`) |
| Localization | `Loc.swift` has **en + tr only**; fr/de/es/pt/it fall back to English (Windows has all 7) |
| Build | `project.yml` (xcodegen), bundle id `com.dagkan.lastfm-scrobbler`, Team `G7Y47M9B73`, Developer ID export via `ExportOptions.plist`, `build-mac.sh` does archive → export → DMG → notarize → staple → manifests → R2 |
| Compiled? | **No.** Every change since May was written on Windows without a Swift toolchain. Expect Swift 6 strict-concurrency complaints on first build. |

## 2. First session on the Mac (do in this order)

```bash
brew install xcodegen
cd macos && xcodegen generate && open LastFmScrobbler.xcodeproj
```

1. **Make it compile.** Likely spots:
   - `Telemetry.swift` uses `nonisolated(unsafe)` statics + `NSLock`; if the compiler objects, convert to an `actor` or `@MainActor` and drop the lock.
   - `ScrobbleEngine.tick()` is `@MainActor` and awaits `doScrobble` — fine, but `progressTask` captures `[weak self]`; if Swift complains about `Sendable` closures, move the loop body into a `@MainActor` method.
   - `AppState.init` mutates `loaded` then calls `Telemetry.configure(settings:)` with `inout` — straightforward, but `@MainActor` isolation of `Loc` may need `MainActor.assumeIsolated` in non-UI call sites.
   - `GitHubMark` in `AboutView.swift` is a hand-translated octicon path; if it looks off, replace with `Image("github-mark")` from a PNG asset (see `assets/branding/github-mark-white.png` in the repo root).
2. **Run from Xcode, log in**, play a track in Music: Monitor should show the track, the progress bar should advance only while playing, pause should freeze it, and a scrobble should land at the threshold. Check History and the Last.fm profile.
3. **Pause/resume/replay edge cases:** pause for > 2 min and resume (must *not* re-scrobble early), replay the same track after it scrobbled (must scrobble again, subject to the duplicate window), skip mid-track (must not scrobble).
4. **Offline queue:** disconnect Wi-Fi, let a track scrobble → it must land in `pending_scrobbles`; reconnect → flushed within 5 min or on restart.
5. **Telemetry:** on first launch an `install_id` row appears in D1 `lastfm-telemetry.installs` with `app_version = 1.0.0` (check via Cloudflare dashboard / MCP). Toggle it off in Settings › Advanced and confirm no more pings.
6. **Login item** (`SMAppService`): toggle Start at login, reboot or log out/in.

## 3. Release checklist (v1.0.0)

- [ ] `project.yml`: `MARKETING_VERSION` 1.0.0, `CURRENT_PROJECT_VERSION` bump per build
- [ ] `xcrun notarytool store-credentials "lastfm-notary" --apple-id <id> --team-id G7Y47M9B73` (app-specific password)
- [ ] `./build-mac.sh --skip-upload` → open the DMG on a *different* user account or a clean VM: Gatekeeper must show no warning (notarized + stapled)
- [ ] Universal binary: confirm `lipo -archs` on the exported app shows `x86_64 arm64` (xcodebuild with `generic/platform=macOS` does this by default)
- [ ] `./build-mac.sh --notes "Initial macOS release;…"` → verify `https://proxy.lastfm.spacechild.dev/lastfm-scrobbler/macos/latest.json`
- [ ] GitHub release: attach the DMG to a `macos-v1.0.0` tag (keep Windows tags as `vX.Y.Z`), link from README › macOS
- [ ] Test the in-app updater once by publishing 1.0.1 to the macOS channel and letting 1.0.0 pick it up

## 4. Plan after 1.0.0

### 1.1 — Updater parity
- In-place update: download a **zip** instead of a DMG, verify SHA-256, replace the bundle (`NSWorkspace` + `ditto`, or adopt Sparkle 2 with EdDSA keys), relaunch. Keep the DMG for first installs only.
- Background check on launch + every 6 h, same "Later / Install" dialog as Windows with release notes.

### 1.2 — Feature parity with Windows 1.2.22
- Fill fr/de/es/pt/it in `Loc.swift` (copy from `Localization/Loc.cs` + `Loc.Extra.cs`).
- Edit-before-scrobble sheet (`onEditBeforeScrobble` is wired but returns the track unchanged).
- Webhook `stopped` event, artist exclude list, diagnostic log file, daily goal on Monitor, streak.
- Tray/menu-bar: scrobble count this session, last-scrobble tooltip, love from the menu (exists), state badge on the status icon.

### 1.3 — Beyond Apple Music
- `MediaRemote` is private API — don't ship it. Options: Spotify's own `com.spotify.client.PlaybackStateChanged` distributed notification (same pattern as Music, cheap to add), and a generic "Now Playing" source via `MPNowPlayingInfoCenter` is read-only for other apps, so no.
- Sonos/AirPlay: out of scope.

### 1.4 — Hardening
- Swift runtime traps aren't caught by `NSSetUncaughtExceptionHandler`; add MetricKit (`MXCrashDiagnostic`) delivery to `/telemetry/crash` on next launch.
- Hotkeys use a global `NSEvent` monitor → needs Accessibility. Prefer a Carbon `RegisterEventHotKey` implementation (no permission) if people actually enable it.
- Privacy manifest (`PrivacyInfo.xcprivacy`) only matters for the App Store; not needed for Developer ID.

## 5. Known gaps / decisions already made
- Proxy host stays `proxy.lastfm.spacechild.dev` (shared with 330+ Windows installs). Don't change it from the macOS side.
- macOS versions start at **1.0.0** and are independent of the Windows numbering.
- `filterAppleMusicOnly` is a no-op on macOS today (only Apple Music is observed) — keep the setting for parity, make it meaningful when Spotify lands.
- Telemetry `appVersion` is the raw `CFBundleShortVersionString`; D1 rows from macOS are distinguishable only by version shape (1.x vs 1.2.x) — consider sending `platform` once the worker is next touched.
