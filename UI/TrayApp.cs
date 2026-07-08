using System.Drawing.Drawing2D;
using LastFmScrobbler.Core;
using LastFmScrobbler.Data;
using LastFmScrobbler.Models;

namespace LastFmScrobbler.UI;

public class TrayApp : ApplicationContext
{
    private readonly Database        _db;
    private readonly ScrobbleEngine  _engine;
    private readonly AppSettings     _settings;
    private readonly NotifyIcon      _tray;
    private readonly MainForm        _mainForm;
    private readonly HotkeyManager   _hotkeys;
    private readonly UpdateChecker   _updater = new();
    private readonly ToolStripMenuItem _nowPlayingItem;
    private readonly ToolStripMenuItem _scrobbleCountItem;
    private readonly ToolStripMenuItem _copyNowPlayingItem;
    private readonly ToolStripMenuItem _loveItem;
    private readonly ToolStripMenuItem _updateItem;
    private readonly Icon _baseIcon;
    private readonly System.Windows.Forms.Timer _idleTooltipTimer = new() { Interval = 60_000 };
    private int    _sessionScrobbles;
    private Track? _currentTrack;
    private bool   _lastScrobbleFailed;

    public TrayApp(Database db, ScrobbleEngine engine, AppSettings settings)
    {
        _db       = db;
        _engine   = engine;
        _settings = settings;

        _mainForm = new MainForm(_db, _engine, _settings);
        _ = _mainForm.Handle;

        _nowPlayingItem     = new ToolStripMenuItem("Not playing") { Enabled = false };
        _scrobbleCountItem  = new ToolStripMenuItem("0 scrobbles this session") { Enabled = false };
        _copyNowPlayingItem = new ToolStripMenuItem("Copy Now Playing\tCtrl+Alt+C");
        _copyNowPlayingItem.Click += (_, _) => CopyNowPlaying();

        _loveItem = new ToolStripMenuItem("♡ Love\tCtrl+Alt+L") { Enabled = false };
        _loveItem.Click += (_, _) => _mainForm.Invoke(() => _mainForm.ToggleLoveCurrentTrack());

        _updateItem = new ToolStripMenuItem("Check for Updates");
        _updateItem.Click += OnUpdateItemClicked;

        var menu = new ContextMenuStrip();
        menu.Items.Add(_nowPlayingItem);
        menu.Items.Add(_scrobbleCountItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(_copyNowPlayingItem);
        menu.Items.Add(_loveItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Monitor",  null, (_, _) => _mainForm.ShowMonitor());
        menu.Items.Add("Settings", null, (_, _) => _mainForm.ShowSettings());
        menu.Items.Add(_updateItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Exit", null, (_, _) => ExitApp());

        _baseIcon = Icon.ExtractAssociatedIcon(Application.ExecutablePath) ?? SystemIcons.Application;

        _tray = new NotifyIcon
        {
            Icon             = _baseIcon,
            Text             = "Last.fm Scrobbler",
            Visible          = true,
            ContextMenuStrip = menu,
        };
        _tray.DoubleClick += (_, _) => _mainForm.ShowMonitor();

        _idleTooltipTimer.Tick += (_, _) => { if (_currentTrack is null) UpdateIdleTooltip(); };
        _idleTooltipTimer.Start();

        _engine.ConfirmBeforeScrobble = async track =>
        {
            bool result = false;
            await Task.Run(() => _mainForm.Invoke(() =>
            {
                using var form = new EditTrackForm(track);
                result = form.ShowDialog() == DialogResult.OK;
            }));
            return result;
        };

        _engine.NowPlayingChanged += OnNowPlayingChanged;
        _engine.TrackScrobbled   += OnTrackScrobbled;

        // Global hotkeys: Ctrl+Alt+L = Love, Ctrl+Alt+C = Copy
        _hotkeys = new HotkeyManager();
        _hotkeys.Register(Keys.L, () => _mainForm.Invoke(() => _mainForm.ToggleLoveCurrentTrack()));
        _hotkeys.Register(Keys.C, () => _mainForm.Invoke(() => CopyNowPlaying()));

        // First-run users without a session need to see the login screen — show
        // the form. Returning users start in tray and can open via double-click
        // or the tray menu.
        if (string.IsNullOrEmpty(_settings.SessionKey))
            _mainForm.ShowMonitor();

        _ = StartEngineAsync();
        _ = CheckForUpdateAsync(onStartup: true);
    }

    // ── Update ────────────────────────────────────────────────────────────────

    private UpdateChecker.UpdateInfo? _pendingUpdate;
    private bool        _updateDialogOpen;
    private UpdateDialog? _activeUpdateDialog;

    private async Task CheckForUpdateAsync(bool onStartup = false)
    {
        if (onStartup) await Task.Delay(TimeSpan.FromSeconds(5));

        UpdateChecker.UpdateInfo? info;
        try { info = await _updater.CheckAsync(); }
        catch { info = null; }

        void Apply()
        {
            _updateItem.Enabled = true;
            _pendingUpdate      = info;
            _updateItem.Text    = info is null ? "Check for Updates" : $"Install Update v{info.Version}…";

            // Always show dialog when an update is found — balloon tips can be
            // suppressed by Windows Focus Assist or notification settings, but
            // a dialog is always visible to the user.
            if (info is not null && !_updateDialogOpen)
                ShowUpdateDialog(info);
        }

        if (_tray.ContextMenuStrip!.InvokeRequired) _tray.ContextMenuStrip.Invoke(Apply);
        else Apply();
    }

    private void OnUpdateItemClicked(object? sender, EventArgs e)
    {
        ShowUpdateDialog(_pendingUpdate);
    }

    private void ShowUpdateDialog(UpdateChecker.UpdateInfo? preFound)
    {
        if (_updateDialogOpen)
        {
            _activeUpdateDialog?.BringToFront();
            _activeUpdateDialog?.Activate();
            return;
        }

        var accent = ParseAccent(_settings.AccentColor);
        var dlg    = new UpdateDialog(_updater, accent, preFound);
        _activeUpdateDialog = dlg;
        _updateDialogOpen   = true;
        dlg.FormClosed += (_, _) => { _updateDialogOpen = false; _activeUpdateDialog = null; };
        dlg.Show();
        dlg.BringToFront();
        dlg.Activate();
    }

    private static Color ParseAccent(string? hex)
    {
        if (string.IsNullOrWhiteSpace(hex)) return Color.FromArgb(186, 0, 0);
        try { return ColorTranslator.FromHtml(hex); } catch { return Color.FromArgb(186, 0, 0); }
    }

    // ── Engine & tray ─────────────────────────────────────────────────────────

    private void CopyNowPlaying()
    {
        if (_currentTrack is null) return;
        var text = string.IsNullOrEmpty(_currentTrack.Album)
            ? $"{_currentTrack.Artist} — {_currentTrack.Title}"
            : $"{_currentTrack.Artist} — {_currentTrack.Title} ({_currentTrack.Album})";
        Clipboard.SetText(text);
        _tray.ShowBalloonTip(1500, "Copied", text, ToolTipIcon.None);
    }

    private async Task StartEngineAsync()
    {
        try
        {
            await _engine.StartAsync();
            if (!_engine.IsAuthenticated)
                _tray.ShowBalloonTip(4000, "Last.fm Scrobbler",
                    "Not authenticated. Right-click → Settings to log in.", ToolTipIcon.Info);
        }
        catch (Exception ex)
        {
            _tray.ShowBalloonTip(5000, "Startup error", ex.Message, ToolTipIcon.Error);
        }
    }

    private void OnNowPlayingChanged(object? sender, Track? track)
    {
        if (_tray.ContextMenuStrip!.InvokeRequired)
        { _tray.ContextMenuStrip.Invoke(() => OnNowPlayingChanged(sender, track)); return; }

        _currentTrack = track;
        _loveItem.Enabled = track is not null && _engine.IsAuthenticated;

        if (track is null)
        {
            _nowPlayingItem.Text        = "Not playing";
            _copyNowPlayingItem.Enabled = false;
            SetTrayIconState(TrayState.Idle);
            UpdateIdleTooltip();
        }
        else
        {
            var display = $"{track.Artist} – {track.Title}";
            _nowPlayingItem.Text        = Truncate(display, 60);
            _copyNowPlayingItem.Enabled = true;
            _tray.Text                  = Truncate($"♪ {display}", 63);
            SetTrayIconState(TrayState.Playing);

            if (_settings.ShowNowPlayingNotification)
                ShowNowPlayingToast(track, display);
        }
    }

    private void OnTrackScrobbled(object? sender, (Track track, bool success) e)
    {
        if (_tray.ContextMenuStrip!.InvokeRequired)
        { _tray.ContextMenuStrip.Invoke(() => OnTrackScrobbled(sender, e)); return; }

        _lastScrobbleFailed = !e.success;
        SetTrayIconState(e.success ? TrayState.Playing : TrayState.Error);

        if (e.success)
        {
            _sessionScrobbles++;
            _scrobbleCountItem.Text = $"{_sessionScrobbles} scrobble{(_sessionScrobbles == 1 ? "" : "s")} this session";
        }
    }

    // ── Tray icon state badge ────────────────────────────────────────────────

    private enum TrayState { Idle, Playing, Error }
    private Icon? _stateIcon;

    private void SetTrayIconState(TrayState state)
    {
        var color = state switch
        {
            TrayState.Playing => Color.FromArgb(70, 200, 70),
            TrayState.Error    => Color.FromArgb(220, 60, 60),
            _                  => (Color?)null, // Idle — no badge, just the plain icon
        };

        var old = _stateIcon;
        _stateIcon = color is null ? null : BuildBadgedIcon(_baseIcon, color.Value);
        _tray.Icon = _stateIcon ?? _baseIcon;
        if (old is not null) { NativeMethods.DestroyIcon(old.Handle); old.Dispose(); }
    }

    private static Icon BuildBadgedIcon(Icon baseIcon, Color badgeColor)
    {
        using var bmp = baseIcon.ToBitmap();
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            int d = Math.Max(4, bmp.Width / 3);
            var rect = new Rectangle(bmp.Width - d, bmp.Height - d, d, d);
            using var brush = new SolidBrush(badgeColor);
            using var pen = new Pen(Color.FromArgb(200, 0, 0, 0), 1);
            g.FillEllipse(brush, rect);
            g.DrawEllipse(pen, rect);
        }
        var hIcon = bmp.GetHicon();
        return Icon.FromHandle(hIcon);
    }

    private void UpdateIdleTooltip()
    {
        var last = _db.GetLastSuccessfulScrobble();
        _tray.Text = last is null
            ? "Last.fm Scrobbler"
            : Truncate($"Last.fm Scrobbler — last: {FormatRelative(DateTime.UtcNow - last.ScrobbledAt.ToUniversalTime())}", 63);
    }

    private static string FormatRelative(TimeSpan span)
    {
        if (span.TotalMinutes < 1) return "just now";
        if (span.TotalMinutes < 60) return $"{(int)span.TotalMinutes}m ago";
        if (span.TotalHours < 24) return $"{(int)span.TotalHours}h ago";
        return $"{(int)span.TotalDays}d ago";
    }

    // ── Toast notification (best-effort; falls back to the classic balloon tip) ─

    private void ShowNowPlayingToast(Track track, string display)
    {
        try
        {
            var thumbPath = SaveThumbnailToTemp();
            var builder = new CommunityToolkit.WinUI.Notifications.ToastContentBuilder()
                .AddText("Now Playing")
                .AddText(display);
            if (thumbPath is not null)
                builder.AddInlineImage(new Uri(thumbPath));
            builder.Show();
        }
        catch
        {
            // Toast requires AUMID/registration plumbing that can be flaky on some
            // Windows configurations — silently fall back to the classic balloon tip.
            _tray.ShowBalloonTip(2000, "Now Playing", display, ToolTipIcon.None);
        }
    }

    private string? SaveThumbnailToTemp()
    {
        try
        {
            var img = _engine.GetCurrentThumbnailAsync().GetAwaiter().GetResult();
            if (img is null) return null;
            var path = Path.Combine(Path.GetTempPath(), "lastfm_scrobbler_now_playing.png");
            img.Save(path, System.Drawing.Imaging.ImageFormat.Png);
            return path;
        }
        catch { return null; }
    }

    private void ExitApp()
    {
        _idleTooltipTimer.Stop();
        _idleTooltipTimer.Dispose();
        _hotkeys.Dispose();
        _tray.Visible = false;
        _mainForm.Dispose();
        _engine.Dispose();
        _db.Dispose();
        if (_stateIcon is not null) { NativeMethods.DestroyIcon(_stateIcon.Handle); _stateIcon.Dispose(); }
        Application.Exit();
    }

    private static string Truncate(string s, int max) =>
        s.Length <= max ? s : s[..(max - 1)] + "…";

    private static class NativeMethods
    {
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern bool DestroyIcon(IntPtr handle);
    }
}
