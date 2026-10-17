using LastFmScrobbler.Data;
using LastFmScrobbler.Core;
using LastFmScrobbler.UI;
using LastFmScrobbler.Localization;

namespace LastFmScrobbler;

internal static class Program
{
    // Top-level statements can't carry [STAThread], so the UI thread used to run
    // as MTA — fine for most of WinForms, but Clipboard, ColorDialog and the file
    // dialogs all throw ThreadStateException on an MTA thread.
    [STAThread]
    private static void Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);

        // Prevent multiple instances
        using var mutex = new System.Threading.Mutex(true, "LastFmScrobblerSingleInstance", out bool firstInstance);
        if (!firstInstance)
        {
            MessageBox.Show("Last.fm Scrobbler is already running.\nCheck the system tray.",
                "Already running", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        // Determine data directory: prefer portable (same dir as exe), fall back to AppData
        var dataDir = GetDataDirectory();
        var dbPath = Path.Combine(dataDir, "lastfm_scrobbler.db");

        using var db = new Database(dbPath);
        var settings = db.LoadSettings();

        FileLogger.Configure(dataDir, settings.EnableDiagnosticLog);
        Loc.SetLanguage(settings.Language);

        Telemetry.Configure(settings, s => db.SaveSettings(s));
        Telemetry.InstallCrashHandlers();

        using var engine = new ScrobbleEngine(db, settings);
        using var trayApp = new TrayApp(db, engine, settings);

        Telemetry.Ping();
        Application.Run(trayApp);
    }

    private static string GetDataDirectory()
    {
        try
        {
            var exeDir = Path.GetDirectoryName(AppContext.BaseDirectory) ?? ".";
            var testFile = Path.Combine(exeDir, ".write_test");
            File.WriteAllText(testFile, "");
            File.Delete(testFile);
            return exeDir; // portable: writable next to exe
        }
        catch
        {
            // Fall back to AppData (e.g., if installed in Program Files)
            var appData = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "LastFmScrobbler");
            Directory.CreateDirectory(appData);
            return appData;
        }
    }
}
