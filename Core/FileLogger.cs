namespace LastFmScrobbler.Core;

/// <summary>
/// Optional flat-file diagnostic log (Settings → "Write a diagnostic log file"). Useful for
/// tracking down issues that are hard to reproduce interactively (AV interference, SMTC
/// quirks on a specific player, etc.) without needing a debugger attached.
/// </summary>
public static class FileLogger
{
    private const long MaxBytes = 2 * 1024 * 1024; // rotate at ~2 MB
    private static readonly object _lock = new();
    private static string? _path;
    private static bool _enabled;

    public static void Configure(string directory, bool enabled)
    {
        lock (_lock)
        {
            _path = Path.Combine(directory, "diagnostic.log");
            _enabled = enabled;
        }
    }

    public static void Log(string message)
    {
        lock (_lock)
        {
            if (!_enabled || _path is null) return;
            try
            {
                if (File.Exists(_path) && new FileInfo(_path).Length > MaxBytes)
                {
                    // Keep the newest half instead of growing forever.
                    var lines = File.ReadAllLines(_path);
                    File.WriteAllLines(_path, lines[(lines.Length / 2)..]);
                }
                File.AppendAllText(_path, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}  {message}{Environment.NewLine}");
            }
            catch { /* best-effort — never let logging crash the app */ }
        }
    }
}
