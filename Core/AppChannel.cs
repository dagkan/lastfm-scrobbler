namespace LastFmScrobbler.Core;

/// <summary>
/// Release vs. beta channel. A beta build (compiled with -p:Beta=true) installs
/// side-by-side with the release: own mutex, own data folder, own Run key, own
/// Inno Setup AppId and its own update manifests under /lastfm-scrobbler/beta/,
/// so the real auto-update flow can be exercised without touching the release.
/// </summary>
public static class AppChannel
{
#if BETA
    public const bool   IsBeta        = true;
    public const string Suffix        = "-beta";
    public const string DisplayName   = "Last.fm Scrobbler Beta";
    public const string MutexName     = "LastFmScrobblerBetaSingleInstance";
    public const string DataDirName   = "LastFmScrobblerBeta";
    public const string RunKeyName    = "LastFmScrobblerBeta";
    public const string UpdatePrefix  = "/lastfm-scrobbler/beta";
#else
    public const bool   IsBeta        = false;
    public const string Suffix        = "";
    public const string DisplayName   = "Last.fm Scrobbler";
    public const string MutexName     = "LastFmScrobblerSingleInstance";
    public const string DataDirName   = "LastFmScrobbler";
    public const string RunKeyName    = "LastFmScrobbler";
    public const string UpdatePrefix  = "/lastfm-scrobbler";
#endif
}
