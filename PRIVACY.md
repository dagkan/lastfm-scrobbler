# Privacy Policy — Last.fm Scrobbler

_Last updated: 2026-11-16_

Last.fm Scrobbler (Windows and macOS) sends what you listen to in Apple Music to your own Last.fm account. It is an independent app and is not affiliated with Last.fm or Apple.

## What stays on your device
- Your Last.fm session key, settings, scrobble history, offline queue and normalization rules are stored only on your computer (in the app's local database).
- The app never sees your Last.fm password.

## What is sent, and to whom
- **Last.fm:** the track, artist, album and time of what you play, and Love/Unlove actions, so they can be scrobbled to your account. This goes through a small proxy we run on Cloudflare (`proxy.lastfm.spacechild.dev`) that only forwards requests to Last.fm and does not store them.
- **Anonymous statistics and crash reports (optional):** a random install ID, the app version, a count of scrobbles, and technical error details if the app crashes. They never include track names, artists or your Last.fm username. You can switch this off in Settings › Advanced.
- **Update check:** the app asks our server for the latest version number.

## What we don't do
- No ads, no tracking across other apps or websites, no selling or sharing of data.
- No account with us is needed.

## Deleting your data
Quit the app and delete its local data folder to remove everything stored on your device. To remove the anonymous install ID from our statistics, contact us with the ID shown in Settings.

## Contact
Open an issue at https://github.com/dagkan/lastfm-scrobbler/issues
