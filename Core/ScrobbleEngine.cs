using LastFmScrobbler.Data;
using LastFmScrobbler.Models;

namespace LastFmScrobbler.Core;

/// <summary>
/// Orchestrates: media detection → normalization → timing → scrobbling.
/// </summary>
public class ScrobbleEngine : IDisposable
{
    public event EventHandler<Track?>? NowPlayingChanged;
    public event EventHandler<(Track track, bool success)>? TrackScrobbled;
    public event EventHandler<int>? PendingQueueFlushed; // arg = number of scrobbles sent

    private readonly Database _db;
    private readonly MediaWatcher _watcher;
    private readonly TrackNormalizer _normalizer;
    private readonly LastFmClient _lfm;

    private AppSettings _settings;
    private Track? _currentTrack;
    private DateTime _trackStartedAt;
    private System.Threading.Timer? _progressTimer;
    private System.Threading.Timer? _retryTimer;
    private int _trackGeneration;
    private readonly object _lock = new();

    // Accumulated-listen-time state (guarded by _lock) — replaces the old one-shot
    // wall-clock timer so pausing freezes the countdown instead of it firing regardless.
    private long _playedMs;
    private int _thresholdMs;
    // Monotonic clock (Environment.TickCount64), not wall time: a wall-clock step
    // backwards (sleep/resume, NTP sync, manual clock change) used to produce a
    // negative delta that drove _playedMs hours into the negative and crashed the
    // UI progress bar every tick.
    private long _lastPollTicks;
    private int _scrobbledGeneration = -1;

    // ── Repeat-play fallback state (guarded by _lock) ────────────────────────
    // MediaWatcher reports a repeat when it sees the timeline wrap. If that wrap is
    // never observed (a player that barely updates its timeline, or unlucky timing),
    // nothing would ever start a new play for a looping track. So keep counting the
    // time played in the *current* play even after it has scrobbled; once that
    // exceeds the track's length while the same item is still playing from near its
    // start, the track must have started over.
    private long _listenedMs;      // like _playedMs, but keeps counting after the scrobble
    private long _playStartTicks;  // monotonic time the current play was started
    private Track? _currentRawTrack; // pre-normalization identity of _currentTrack
    // True when the current play began as a detected repeat (timeline wrap or the
    // fallback above). Such a play is a real new listen, so it skips the duplicate window.
    private bool _currentPlayIsRepeat;

    // (The decision itself is RepeatDetector.LoopedWithoutWrap.)
    // A same-track repeat signal this soon after a play began is the same loop being
    // reported twice (watcher + fallback, or a duplicated event) — ignore it.
    private const int RepeatGuardMs = 20_000;

    private readonly Dictionary<(string artist, string title), string> _albumCache =
        new(new AlbumCacheComparer());

    private sealed class AlbumCacheComparer : IEqualityComparer<(string artist, string title)>
    {
        public bool Equals((string artist, string title) x, (string artist, string title) y) =>
            string.Equals(x.artist, y.artist, StringComparison.OrdinalIgnoreCase) &&
            string.Equals(x.title, y.title, StringComparison.OrdinalIgnoreCase);
        public int GetHashCode((string artist, string title) k) =>
            HashCode.Combine(k.artist.ToLowerInvariant(), k.title.ToLowerInvariant());
    }

    // Raised when the engine wants the UI to confirm/edit a track before scrobbling.
    public Func<Track, Task<bool>>? ConfirmBeforeScrobble { get; set; }

    public ScrobbleEngine(Database db, AppSettings settings)
    {
        _db = db;
        _settings = settings;

        _normalizer = new TrackNormalizer();
        ReloadRules();

        _watcher = new MediaWatcher();
        _watcher.TrackChanged += OnTrackChanged;

        _lfm = new LastFmClient();
        ApplyCredentials();
    }

    public void ApplyCredentials()
    {
        _lfm.Configure(_settings.SessionKey);
    }

    public void UpdateSettings(AppSettings settings)
    {
        _settings = settings;
        ApplyCredentials();
        _watcher.UpdateFilter(settings.FilterAppleMusicOnly);
        ReloadRules();
        FileLogger.Configure(_db.DataDirectory, settings.EnableDiagnosticLog);
    }

    public void ReloadRules()
    {
        var rules = _db.LoadRules();
        _normalizer.UpdateRules(rules);
    }

    public async Task StartAsync()
    {
        await _watcher.StartAsync(_settings.FilterAppleMusicOnly);
        _ = FlushPendingQueueAsync();
        _retryTimer = new System.Threading.Timer(
            _ => _ = FlushPendingQueueAsync(),
            null,
            TimeSpan.FromMinutes(5),
            TimeSpan.FromMinutes(5));
        _lastPollTicks = Environment.TickCount64;
        _progressTimer = new System.Threading.Timer(
            _ => OnProgressTick(),
            null,
            TimeSpan.FromSeconds(1),
            TimeSpan.FromSeconds(1));
    }

    /// <summary>Accumulated played-ms and the scrobble target for the current track — used by the UI progress bar.</summary>
    public (long playedMs, int thresholdMs) GetScrobbleProgress()
    {
        lock (_lock) return (_playedMs, _thresholdMs);
    }

    public bool IsAuthenticated => _lfm.IsAuthenticated;
    public LastFmClient LastFmClient => _lfm;
    public Track? CurrentTrack => _currentTrack;

    // ── Track Change ─────────────────────────────────────────────────────────

    private void OnTrackChanged(object? sender, Track? rawTrack)
    {
        lock (_lock)
        {
            if (rawTrack is null)
            {
                FileLogger.Log("now_playing: (stopped)");
                _currentTrack = null;
                _currentRawTrack = null;
                NowPlayingChanged?.Invoke(this, null);
                if (_settings.WebhookOnNowPlaying)
                    WebhookClient.Post(_settings.WebhookUrl, "stopped", null);
                return;
            }

            var track = _settings.AutoNormalize ? _normalizer.Normalize(rawTrack) : rawTrack;

            if (IsExcludedArtist(track.Artist))
            {
                FileLogger.Log($"excluded artist, skipping: {track.Artist} — {track.Title}");
                _currentTrack = null;
                _currentRawTrack = null;
                NowPlayingChanged?.Invoke(this, null);
                return;
            }

            // The watcher only re-raises the track that is already current when it has
            // detected a repeat (or after a stop, but then _currentTrack is null).
            bool isRepeat = _currentTrack is not null && rawTrack.IsSameTrack(_currentRawTrack);
            if (isRepeat)
            {
                var sinceStartMs = Environment.TickCount64 - _playStartTicks;
                if (sinceStartMs < RepeatGuardMs)
                {
                    FileLogger.Log($"repeat signal ignored ({sinceStartMs} ms after this play started): {track.Artist} — {track.Title}");
                    return;
                }
            }

            FileLogger.Log(isRepeat
                ? $"now_playing (repeat, timeline wrap): {track.Artist} — {track.Title} [{track.SourceApp}]"
                : $"now_playing: {track.Artist} — {track.Title} [{track.SourceApp}]");

            _currentRawTrack = rawTrack;
            BeginPlay(track, seedPlayedMs: 0, isRepeat: isRepeat);
        }
    }

    /// <summary>
    /// Starts a new play of <paramref name="track"/>: new generation, fresh listen-time
    /// accumulators, now-playing notifications. <paramref name="seedPlayedMs"/> is how far
    /// into the track playback already is (0 for a normal start). <paramref name="isRepeat"/>
    /// marks a play that began as a detected loop of the current track, which exempts it
    /// from the duplicate window. Caller holds _lock.
    /// </summary>
    private void BeginPlay(Track track, long seedPlayedMs, bool isRepeat)
    {
        _currentTrack = track;
        _currentPlayIsRepeat = isRepeat;
        _trackStartedAt = DateTime.UtcNow - TimeSpan.FromMilliseconds(seedPlayedMs);
        var gen = ++_trackGeneration;

        // Reset the listen-time accumulators for this (possibly repeated) track.
        _playedMs = seedPlayedMs;
        _listenedMs = seedPlayedMs;
        _thresholdMs = CalculateThresholdMs(track);
        _lastPollTicks = _playStartTicks = Environment.TickCount64;

        NowPlayingChanged?.Invoke(this, track);
        if (_settings.WebhookOnNowPlaying)
            WebhookClient.Post(_settings.WebhookUrl, "now_playing", track);
        _ = ResolveAlbumThenProceedAsync(track, gen);
    }

    private async Task ResolveAlbumThenProceedAsync(Track track, int gen)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(track.Album))
            {
                string? lfmAlbum;
                var cacheKey = (track.Artist, track.Title);
                lock (_lock)
                {
                    if (!_albumCache.TryGetValue(cacheKey, out lfmAlbum))
                        lfmAlbum = null;
                }

                if (lfmAlbum is null)
                {
                    lfmAlbum = await _lfm.GetAlbumNameAsync(track.Artist, track.Title);
                    if (!string.IsNullOrWhiteSpace(lfmAlbum))
                        lock (_lock) _albumCache[cacheKey] = lfmAlbum;
                }

                if (!string.IsNullOrWhiteSpace(lfmAlbum))
                {
                    lock (_lock)
                    {
                        if (gen == _trackGeneration)
                        {
                            track.Album = lfmAlbum;
                            NowPlayingChanged?.Invoke(this, track);
                        }
                    }
                }
            }
        }
        catch { /* keep SMTC album as fallback */ }

        lock (_lock)
        {
            if (gen != _trackGeneration) return;
        }

        await SendNowPlayingAsync(track);
    }

    private async Task SendNowPlayingAsync(Track track)
    {
        if (!_lfm.IsAuthenticated) return;
        try { await _lfm.UpdateNowPlayingAsync(track); }
        catch { /* not critical */ }
    }

    // ── Excluded Artists ─────────────────────────────────────────────────────

    private bool IsExcludedArtist(string artist)
    {
        if (string.IsNullOrWhiteSpace(_settings.ExcludedArtists) || string.IsNullOrWhiteSpace(artist))
            return false;
        return _settings.ExcludedArtists
            .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Any(excluded => artist.Contains(excluded, StringComparison.OrdinalIgnoreCase));
    }

    // ── Scrobble Timing ──────────────────────────────────────────────────────

    private int CalculateThresholdMs(Track track)
    {
        int minMs = _settings.ScrobbleMinSeconds * 1000;

        if (track.DurationSeconds.HasValue && track.DurationSeconds > 0)
        {
            int byPercent = (int)(track.DurationSeconds.Value * 1000 * _settings.ScrobbleThresholdPercent / 100.0);
            // Never schedule at/after the track's natural end — SMTC has often already
            // advanced to the next track by then and the scrobble silently drops.
            int cap = Math.Max(0, track.DurationSeconds.Value * 1000 - 5000);
            byPercent = Math.Min(byPercent, cap);
            int byMax = _settings.ScrobbleThresholdMaxSeconds * 1000;
            return Math.Max(minMs, Math.Min(byPercent, byMax));
        }

        return Math.Max(minMs, (int)(_settings.ScrobbleThresholdMaxSeconds * 1000 * _settings.ScrobbleThresholdPercent / 100.0));
    }

    // ── Listen-time polling ──────────────────────────────────────────────────

    private void OnProgressTick()
    {
        var state = _watcher.GetPlaybackState(); // read before taking _lock — no nested lock ordering
        // Also feeds the watcher's repeat detector, so a wrap is noticed even when
        // TimelinePropertiesChanged is not delivered for it.
        var timeline = _watcher.PollTimeline();
        var now = Environment.TickCount64;
        Track? track = null;
        DateTime startedAt = default;
        int gen = 0;
        bool isRepeatPlay = false;
        bool fire = false;

        lock (_lock)
        {
            if (_currentTrack is null) { _lastPollTicks = now; return; }

            var deltaMs = Math.Clamp(now - _lastPollTicks, 0, 2000);
            _lastPollTicks = now;
            if (state == PlaybackState.Playing)
                _listenedMs += deltaMs;

            if (IsFallbackRepeat(_currentTrack, state, timeline, out var positionSec))
            {
                var positionMs = (long)(positionSec * 1000);
                FileLogger.Log($"repeat detected (engine fallback, no timeline wrap seen): {_currentTrack.Artist} — {_currentTrack.Title} " +
                               $"listened={_listenedMs / 1000}s dur={_currentTrack.DurationSeconds}s pos={positionSec:0.0}s");

                // Same track, new listen. A fresh DetectedAt is what tells the UI this
                // is a new play rather than a metadata refresh of the current one.
                var replay = _currentTrack.Clone();
                replay.DetectedAt = DateTime.UtcNow;
                // Seed from the live position so the scrobble point and the reported
                // start time line up with the real loop, not with when we noticed it.
                BeginPlay(replay, seedPlayedMs: Math.Max(0, positionMs), isRepeat: true);
                return;
            }

            gen = _trackGeneration;
            if (_scrobbledGeneration == gen) return;

            if (state == PlaybackState.Playing)
                _playedMs += deltaMs;

            if (_thresholdMs > 0 && _playedMs >= _thresholdMs)
            {
                _scrobbledGeneration = gen;
                track = _currentTrack;
                startedAt = _trackStartedAt;
                isRepeatPlay = _currentPlayIsRepeat;
                fire = true;
            }
        }

        if (fire && track is not null)
            _ = DoScrobbleAsync(track, startedAt, gen, isRepeatPlay);
    }

    /// <summary>
    /// True when the current track has been playing for longer than it lasts and the
    /// live timeline shows the same item playing from near its start — i.e. it looped
    /// without the watcher seeing the wrap. Caller holds _lock.
    /// </summary>
    private bool IsFallbackRepeat(Track current, PlaybackState state, TimelineSnapshot? timeline, out double positionSec)
    {
        positionSec = 0;
        if (state != PlaybackState.Playing) return false;
        if (timeline is not { IsPlaying: true } tl) return false;
        if (!RepeatDetector.LoopedWithoutWrap(_listenedMs, current.DurationSeconds, tl.PositionSeconds, tl.EndSeconds))
            return false;
        positionSec = Math.Max(0, tl.PositionSeconds);
        return true;
    }

    // ── Scrobble ─────────────────────────────────────────────────────────────

    private async Task DoScrobbleAsync(Track track, DateTime startedAt, int gen, bool isRepeatPlay)
    {
        lock (_lock)
        {
            if (gen != _trackGeneration || !track.IsSameTrack(_currentTrack)) return;
        }

        Track scrobbleTrack = track;

        if (_settings.EditBeforeScrobble && ConfirmBeforeScrobble is not null)
        {
            var proceed = await ConfirmBeforeScrobble(scrobbleTrack);
            if (!proceed) return;
        }

        // Duplicate suppression: stops the same listen being sent twice (e.g. after an
        // app restart mid-track). A detected repeat is a real new listen, so it is exempt —
        // otherwise every other loop of a track shorter than the window would be dropped.
        if (!isRepeatPlay &&
            _settings.DuplicateWindowMinutes > 0 &&
            _db.WasRecentlyScrobbled(scrobbleTrack.Artist, scrobbleTrack.Title, _settings.DuplicateWindowMinutes))
        {
            FileLogger.Log($"scrobble skipped (duplicate window {_settings.DuplicateWindowMinutes} min): {scrobbleTrack.Artist} — {scrobbleTrack.Title}");
            return;
        }

        bool success = false;
        string? error = null;

        try
        {
            if (_lfm.IsAuthenticated)
                success = await _lfm.ScrobbleAsync(scrobbleTrack, startedAt);
        }
        catch (System.Net.Http.HttpRequestException)
        {
            // Network failure — queue for later retry
            _db.AddPendingScrobble(new PendingScrobble
            {
                Title     = scrobbleTrack.Title,
                Artist    = scrobbleTrack.Artist,
                Album     = scrobbleTrack.Album,
                PlayedAt  = startedAt,
                QueuedAt  = DateTime.UtcNow,
            });
            error = "Offline — queued for retry";
        }
        catch (LastFmApiException ex) when (ex.Code is 11 or 16 or 29)
        {
            // Last.fm-side transient failure (11=temporarily unavailable, 16=temporary
            // failure, 29=rate limited) — worth a retry, unlike e.g. bad session/params.
            _db.AddPendingScrobble(new PendingScrobble
            {
                Title     = scrobbleTrack.Title,
                Artist    = scrobbleTrack.Artist,
                Album     = scrobbleTrack.Album,
                PlayedAt  = startedAt,
                QueuedAt  = DateTime.UtcNow,
            });
            error = $"Last.fm temporarily unavailable ({ex.Code}) — queued for retry";
        }
        catch (Exception ex)
        {
            error = ex.Message;
        }

        _db.AddScrobbleRecord(new ScrobbleRecord
        {
            Title        = scrobbleTrack.Title,
            Artist       = scrobbleTrack.Artist,
            Album        = scrobbleTrack.Album,
            ScrobbledAt  = DateTime.UtcNow,
            Success      = success,
            ErrorMessage = error
        });

        FileLogger.Log(success
            ? $"scrobbled: {scrobbleTrack.Artist} — {scrobbleTrack.Title}"
            : $"scrobble FAILED: {scrobbleTrack.Artist} — {scrobbleTrack.Title} ({error})");
        if (success) Telemetry.Scrobble(1);

        TrackScrobbled?.Invoke(this, (scrobbleTrack, success));
        if (_settings.WebhookOnScrobble)
            WebhookClient.Post(_settings.WebhookUrl, "scrobbled", scrobbleTrack, success);
    }

    // ── Manual Scrobble ───────────────────────────────────────────────────────

    public async Task<bool> ManualScrobbleAsync(string artist, string title, string album, DateTime playedAt)
    {
        var track  = new Track { Artist = artist, Title = title, Album = album };
        bool success = false;
        string? error = null;

        try
        {
            if (_lfm.IsAuthenticated)
                success = await _lfm.ScrobbleAsync(track, playedAt);
        }
        catch (Exception ex)
        {
            error = ex.Message;
        }

        _db.AddScrobbleRecord(new ScrobbleRecord
        {
            Title        = title,
            Artist       = artist,
            Album        = album,
            ScrobbledAt  = DateTime.UtcNow,
            Success      = success,
            ErrorMessage = error
        });

        TrackScrobbled?.Invoke(this, (track, success));
        return success;
    }

    // ── Love / Unlove ─────────────────────────────────────────────────────────

    public async Task LoveTrackAsync(Track track, bool love)
    {
        try
        {
            if (love) await _lfm.LoveTrackAsync(track.Artist, track.Title);
            else      await _lfm.UnloveTrackAsync(track.Artist, track.Title);
        }
        catch { /* best-effort */ }
    }

    // ── Offline Queue Flush ───────────────────────────────────────────────────

    public async Task FlushPendingQueueAsync()
    {
        if (!_lfm.IsAuthenticated) return;

        var pending = _db.LoadPendingScrobbles();
        if (pending.Count == 0) return;

        var items = pending
            .Select(p => (new Track { Artist = p.Artist, Title = p.Title, Album = p.Album }, p.PlayedAt))
            .ToList();

        try
        {
            int sent = await _lfm.ScrobbleBatchAsync(items);
            foreach (var p in pending)
                _db.DeletePendingScrobble(p.Id);

            if (sent > 0)
            {
                Telemetry.Scrobble(sent);
                PendingQueueFlushed?.Invoke(this, sent);
            }
        }
        catch { /* still offline — try again next tick */ }
    }

    // ── Album Art ─────────────────────────────────────────────────────────────

    public Task<System.Drawing.Image?> GetCurrentThumbnailAsync() =>
        _watcher.GetCurrentThumbnailAsync();

    // ── Dispose ───────────────────────────────────────────────────────────────

    public void Dispose()
    {
        _progressTimer?.Dispose();
        _retryTimer?.Dispose();
        _watcher.Dispose();
    }
}
