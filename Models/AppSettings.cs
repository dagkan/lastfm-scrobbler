namespace LastFmScrobbler.Models;

public class AppSettings
{
    public string? SessionKey { get; set; }
    public string? Username { get; set; }

    // Scrobble threshold: 10–100 (percent of track duration)
    public int ScrobbleThresholdPercent { get; set; } = 50;

    // Also scrobble if played longer than this many seconds (Last.fm rule: 4 min cap)
    public int ScrobbleThresholdMaxSeconds { get; set; } = 240;

    // Minimum seconds before any scrobble (Last.fm rule: at least 30s)
    public int ScrobbleMinSeconds { get; set; } = 30;

    public bool AutoNormalize { get; set; } = true;
    public bool FilterAppleMusicOnly { get; set; } = true;
    public bool EditBeforeScrobble { get; set; } = false;
    public bool StartWithWindows { get; set; } = false;
    public bool ShowNowPlayingNotification { get; set; } = false;

    // 0 = disabled; skip scrobble if the same track was scrobbled within this window
    public int DuplicateWindowMinutes { get; set; } = 5;

    public string AccentColor { get; set; } = "#BA0000";

    public string Language { get; set; } = "en";

    public int DailyScrobbleGoal { get; set; } = 0;

    public string WebhookUrl { get; set; } = "";
    public bool WebhookOnScrobble { get; set; } = true;
    public bool WebhookOnNowPlaying { get; set; } = false;

    // Newline-separated artist names/substrings — a track whose Artist contains any of these
    // (case-insensitive) is never scrobbled or timed.
    public string ExcludedArtists { get; set; } = "";

    public bool EnableDiagnosticLog { get; set; } = false;

    // Anonymous usage/crash telemetry (opt-out). InstallId is a random 32-hex id
    // generated on first run — it is the only identity ever sent.
    public bool    TelemetryEnabled { get; set; } = true;
    public string? InstallId        { get; set; }

    // Global hotkeys default off: Ctrl+Alt is AltGr on many layouts, so an
    // always-on Ctrl+Alt+L / C silently swallows ł / ć / etc. while typing.
    public bool EnableGlobalHotkeys { get; set; } = false;
}
