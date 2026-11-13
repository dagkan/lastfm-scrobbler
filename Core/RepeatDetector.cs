namespace LastFmScrobbler.Core;

/// <summary>
/// Detects "the same track started over" (Repeat One, or a manual replay) from a
/// stream of timeline samples. SMTC raises no metadata event for that — title and
/// artist are unchanged — so the only evidence is the position wrapping from the
/// end of the track back to its start.
///
/// Deliberately free of WinRT types and of any clock: it is a small state machine
/// fed with (track key, position, duration, playing?) samples, so it can be driven
/// from both the timeline event and a 1-second poll, and tested in isolation.
///
/// Not thread-safe; the caller serialises <see cref="Observe"/> / <see cref="Reset"/>.
/// </summary>
public sealed class RepeatDetector
{
    /// <summary>Tracks shorter than this are never treated as repeating (Last.fm ignores them anyway).</summary>
    public const double MinDurationSec = 30;
    /// <summary>A sample within this many seconds of the end arms the detector.</summary>
    public const double EndZoneSec = 12;
    /// <summary>An armed detector fires on the first playing sample at or below this position.</summary>
    public const double StartZoneSec = 10;
    /// <summary>
    /// If the reported duration moves by more than this between arming and the wrap,
    /// the timeline is describing a different item (the next track, whose metadata
    /// event simply has not arrived yet) — that is a track change, not a repeat.
    /// </summary>
    public const double DurationToleranceSec = 2;

    private string? _key;
    private bool _armed;
    private double _armedDurationSec;

    /// <summary>True once a sample near the end has been seen and the wrap is still awaited.</summary>
    public bool IsArmed => _armed;

    /// <summary>Forget everything (session lost, playback stopped).</summary>
    public void Reset()
    {
        _key = null;
        _armed = false;
        _armedDurationSec = 0;
    }

    /// <summary>
    /// Feed one timeline sample. Returns true exactly once per observed wrap of the
    /// same track from its end zone to its start zone.
    /// </summary>
    /// <param name="key">Identity of the track the caller believes is playing (e.g. "Title|Artist").</param>
    /// <param name="positionSec">Reported playback position.</param>
    /// <param name="durationSec">Reported track length; &lt;= 0 means "not known right now".</param>
    /// <param name="isPlaying">Whether the player reports Playing for this sample.</param>
    public bool Observe(string key, double positionSec, double durationSec, bool isPlaying)
    {
        if (!string.Equals(key, _key, StringComparison.Ordinal))
        {
            _key = key;
            _armed = false;
        }

        // No usable timeline in this sample (players blank it for a moment between
        // tracks). Keep whatever state we have — dropping it here is exactly how a
        // loop used to get lost.
        if (double.IsNaN(positionSec) || double.IsNaN(durationSec) || durationSec <= 0)
            return false;

        if (durationSec < MinDurationSec)
        {
            _armed = false;
            return false;
        }

        if (_armed && Math.Abs(durationSec - _armedDurationSec) > DurationToleranceSec)
            _armed = false; // a different item now owns the timeline — evaluate it afresh below

        if (positionSec >= durationSec - EndZoneSec)
        {
            _armed = true;
            _armedDurationSec = durationSec;
            return false;
        }

        if (positionSec <= StartZoneSec)
        {
            if (!_armed) return false;
            // Wrapped, but the player is still Paused/Stopped/Changing: stay armed and
            // let the first Playing sample in the start zone report the repeat.
            if (!isPlaying) return false;
            _armed = false;
            return true;
        }

        // Somewhere in the middle: a seek away from the end, or the start-zone
        // window was missed entirely. Either way this is no longer a clean wrap.
        _armed = false;
        return false;
    }

    // ── Fallback for a wrap that was never observed ──────────────────────────

    /// <summary>
    /// How far past the track's length the accumulated listening time must be before
    /// <see cref="LoopedWithoutWrap"/> may say yes. Larger than <see cref="StartZoneSec"/>,
    /// so <see cref="Observe"/> always gets the first go at a loop.
    /// </summary>
    public const int OverrunMs = 15_000;
    /// <summary>The live end time must match the track's known length within this.</summary>
    public const double EndToleranceSec = 3;
    /// <summary>Upper bound for "near the start" (further capped at half the track).</summary>
    public const double MaxRestartPositionSec = 45;

    /// <summary>
    /// The safety net for players/timings where the wrap itself is never sampled:
    /// true when a track has been playing (not merely on screen) for longer than it
    /// lasts, and the live timeline shows the same-length item playing from near its
    /// start — so it must have started over. Call only while the player is Playing.
    /// </summary>
    /// <param name="listenedMs">Time actually spent playing since this play began.</param>
    /// <param name="trackDurationSec">The track's known length, if any.</param>
    /// <param name="positionSec">Live position.</param>
    /// <param name="endSec">Live end time. A live stream's growing end time never matches.</param>
    public static bool LoopedWithoutWrap(long listenedMs, int? trackDurationSec, double positionSec, double endSec)
    {
        if (trackDurationSec is not int dur || dur < MinDurationSec) return false;
        if (double.IsNaN(positionSec) || double.IsNaN(endSec)) return false;
        if (listenedMs < dur * 1000L + OverrunMs) return false;
        // Same item still on the timeline?
        if (Math.Abs(endSec - dur) > EndToleranceSec) return false;
        // Near the start — a stalled-but-"Playing" player sits wherever it stalled.
        return positionSec <= Math.Min(MaxRestartPositionSec, dur / 2.0);
    }
}
