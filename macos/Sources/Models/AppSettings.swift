import Foundation

struct AppSettings: Sendable {
    var sessionKey: String = ""
    var username: String = ""

    var scrobbleThresholdPercent: Int = 50
    var scrobbleThresholdMaxSeconds: Int = 240
    var scrobbleMinSeconds: Int = 30

    var autoNormalize: Bool = true
    var filterAppleMusicOnly: Bool = true
    var editBeforeScrobble: Bool = false
    var startAtLogin: Bool = false
    var showNowPlayingNotification: Bool = false
    var duplicateWindowMinutes: Int = 5

    var accentColor: String = "#BA0000"
    var language: String = "en"
    var dailyScrobbleGoal: Int = 0

    var webhookUrl: String = ""
    var webhookOnScrobble: Bool = true
    var webhookOnNowPlaying: Bool = false

    // Anonymous usage/crash telemetry (opt-out). installId is a random 32-hex
    // id generated on first run — the only identity ever sent.
    var telemetryEnabled: Bool = true
    var installId: String = ""

    // Global hotkeys (⌃⌥L / ⌃⌥C) are opt-in: they need the Accessibility
    // permission and can shadow layout-specific key combos.
    var enableGlobalHotkeys: Bool = false
}
