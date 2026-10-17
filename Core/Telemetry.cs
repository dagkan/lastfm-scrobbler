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
        Post("crash", new
        {
            exceptionType = ex.GetType().FullName ?? "Unknown",
            message       = ex.Message,
            stackTrace    = ex.ToString(),
        });
    }

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
        var task = _http.PostAsJsonAsync(Base + "crash", WithIdentity(new
        {
            exceptionType = ex.GetType().FullName ?? "Unknown",
            message       = ex.Message,
            stackTrace    = ex.ToString(),
        }));
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
