using System.Net.Http;
using System.Net.Http.Json;
using System.Security.Cryptography;
using LastFmScrobbler.Models;

namespace LastFmScrobbler.Core;

/// <summary>
/// Anonymous, opt-out usage pings and crash reports. Only ever sends a random
/// install id, the app version and exception type/message/stack — never track,
/// artist, username or any Last.fm data. Toggle lives in Settings › Advanced.
/// </summary>
public static class Telemetry
{
    private const string Base = "https://proxy.lastfm.spacechild.dev/telemetry/";

    private static readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(10) };
    private static AppSettings? _settings;
    private static Action<AppSettings>? _save;

    // Same exception (type + message) within this window is reported once —
    // a timer-driven fault would otherwise flood the backend every tick.
    private static readonly TimeSpan DedupeWindow = TimeSpan.FromMinutes(10);
    private static readonly Dictionary<string, DateTime> _recentCrashes = new();
    private static readonly object _crashLock = new();

    public static void Configure(AppSettings settings, Action<AppSettings> save)
    {
        _settings = settings;
        _save     = save;

        if (string.IsNullOrEmpty(settings.InstallId) || settings.InstallId.Length != 32)
        {
            settings.InstallId = Convert.ToHexString(RandomNumberGenerator.GetBytes(16)).ToLowerInvariant();
            try { save(settings); } catch { }
        }
    }

    public static bool Enabled => _settings?.TelemetryEnabled ?? false;

    public static void Ping()           => Post("ping",     new { });
    public static void Scrobble(int n)  => Post("scrobble", new { count = n });

    public static void Crash(Exception ex)
    {
        var key = ex.GetType().FullName + "|" + ex.Message;
        lock (_crashLock)
        {
            var now = DateTime.UtcNow;
            if (_recentCrashes.TryGetValue(key, out var last) && now - last < DedupeWindow) return;
            _recentCrashes[key] = now;
        }
        Post("crash", CrashPayload(ex));
    }

    /// <summary>
    /// Exception text can embed local paths (and with them the Windows user name)
    /// — e.g. a FileNotFoundException under %APPDATA%. Scrub those before sending.
    /// </summary>
    private static string Scrub(string s)
    {
        if (string.IsNullOrEmpty(s)) return s;
        var profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (!string.IsNullOrEmpty(profile))
            s = s.Replace(profile, "%USERPROFILE%", StringComparison.OrdinalIgnoreCase);
        var user = Environment.UserName;
        if (!string.IsNullOrEmpty(user) && user.Length > 2)
            s = s.Replace(user, "<user>", StringComparison.OrdinalIgnoreCase);
        return s;
    }

    private static object CrashPayload(Exception ex) => new
    {
        exceptionType = ex.GetType().FullName ?? "Unknown",
        message       = Scrub(ex.Message),
        stackTrace    = Scrub(ex.ToString()),
    };

    /// <summary>Wires up WinForms + AppDomain + Task unhandled-exception hooks.</summary>
    public static void InstallCrashHandlers()
    {
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
        Application.ThreadException += (_, e) =>
        {
            FileLogger.Log($"unhandled UI exception: {e.Exception}");
            Crash(e.Exception);
            // UI thread faults are logged and reported but not fatal — the tray
            // app keeps scrobbling, which is what users actually care about.
        };
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
        {
            if (e.ExceptionObject is not Exception ex) return;
            FileLogger.Log($"unhandled exception (terminating={e.IsTerminating}): {ex}");
            // Process is about to die — give the report a moment to leave.
            try { CrashBlocking(ex); } catch { }
        };
        TaskScheduler.UnobservedTaskException += (_, e) =>
        {
            FileLogger.Log($"unobserved task exception: {e.Exception}");
            Crash(e.Exception.GetBaseException());
            e.SetObserved();
        };
    }

    private static void CrashBlocking(Exception ex)
    {
        if (!Enabled) return;
        var task = _http.PostAsJsonAsync(Base + "crash", WithIdentity(CrashPayload(ex)));
        task.Wait(TimeSpan.FromSeconds(3));
    }

    private static void Post(string endpoint, object body)
    {
        if (!Enabled) return;
        _ = Task.Run(async () =>
        {
            try { await _http.PostAsJsonAsync(Base + endpoint, WithIdentity(body)); }
            catch { /* telemetry is best-effort */ }
        });
    }

    private static Dictionary<string, object?> WithIdentity(object body)
    {
        var dict = new Dictionary<string, object?>
        {
            ["installId"]  = _settings?.InstallId,
            ["appVersion"] = UpdateChecker.DisplayVersion,
        };
        foreach (var p in body.GetType().GetProperties())
            dict[p.Name] = p.GetValue(body);
        return dict;
    }
}
