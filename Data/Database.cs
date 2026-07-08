using LastFmScrobbler.Models;
using Microsoft.Data.Sqlite;

namespace LastFmScrobbler.Data;

public class Database : IDisposable
{
    private readonly SqliteConnection _conn;
    private readonly object _lock = new();

    public string DataDirectory { get; }

    public Database(string path)
    {
        DataDirectory = Path.GetDirectoryName(Path.GetFullPath(path)) ?? AppContext.BaseDirectory;
        _conn = new SqliteConnection($"Data Source={path}");
        _conn.Open();
        Migrate();
    }

    private void Migrate()
    {
        Execute(@"
            CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value TEXT
            );
            CREATE TABLE IF NOT EXISTS normalization_rules (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                field TEXT NOT NULL,
                pattern TEXT NOT NULL,
                replacement TEXT NOT NULL DEFAULT '',
                is_enabled INTEGER NOT NULL DEFAULT 1,
                description TEXT NOT NULL DEFAULT '',
                is_builtin INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS scrobble_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                artist TEXT NOT NULL,
                album TEXT NOT NULL DEFAULT '',
                scrobbled_at TEXT NOT NULL,
                success INTEGER NOT NULL DEFAULT 1,
                error_message TEXT
            );
            CREATE TABLE IF NOT EXISTS pending_scrobbles (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                artist TEXT NOT NULL,
                album TEXT NOT NULL DEFAULT '',
                played_at TEXT NOT NULL,
                queued_at TEXT NOT NULL
            );
        ");

        // normalization_rules.app_filter added post-1.2.17 — backfill on existing DBs.
        // Fully materialize + dispose the PRAGMA reader before issuing the ALTER — running
        // DDL while a reader on the same connection is still live is asking for trouble.
        var existingColumns = new List<string>();
        using (var pragma = _conn.CreateCommand())
        {
            pragma.CommandText = "PRAGMA table_info(normalization_rules)";
            using (var r = pragma.ExecuteReader())
                while (r.Read())
                    existingColumns.Add(r.GetString(1));
        }
        if (!existingColumns.Any(c => string.Equals(c, "app_filter", StringComparison.OrdinalIgnoreCase)))
            Execute("ALTER TABLE normalization_rules ADD COLUMN app_filter TEXT NOT NULL DEFAULT ''");

        // Seed default normalization rules if table is empty
        var count = Scalar<long>("SELECT COUNT(*) FROM normalization_rules");
        if (count == 0)
            SeedDefaultRules();
    }

    // ── Settings ────────────────────────────────────────────────────────────

    public AppSettings LoadSettings()
    {
        lock (_lock)
        {
            var settings = new AppSettings();
            using var cmd = _conn.CreateCommand();
            cmd.CommandText = "SELECT key, value FROM settings";
            using var reader = cmd.ExecuteReader();
            while (reader.Read())
            {
                var key = reader.GetString(0);
                var value = reader.IsDBNull(1) ? null : reader.GetString(1);
                switch (key)
                {
                    case "session_key": settings.SessionKey = value; break;
                    case "username": settings.Username = value; break;
                    case "scrobble_threshold_pct": settings.ScrobbleThresholdPercent = int.TryParse(value, out var p) ? p : 50; break;
                    case "scrobble_threshold_max_s": settings.ScrobbleThresholdMaxSeconds = int.TryParse(value, out var m) ? m : 240; break;
                    case "scrobble_min_s": settings.ScrobbleMinSeconds = int.TryParse(value, out var min) ? min : 30; break;
                    case "auto_normalize": settings.AutoNormalize = value != "0"; break;
                    case "filter_apple_music": settings.FilterAppleMusicOnly = value != "0"; break;
                    case "edit_before_scrobble": settings.EditBeforeScrobble = value == "1"; break;
                    case "start_with_windows": settings.StartWithWindows = value == "1"; break;
                    case "show_now_playing_notif": settings.ShowNowPlayingNotification = value == "1"; break;
                    case "duplicate_window_min": settings.DuplicateWindowMinutes = int.TryParse(value, out var dw) ? dw : 5; break;
                    case "accent_color": settings.AccentColor = value ?? "#BA0000"; break;
                    case "language": settings.Language = value ?? "en"; break;
                    case "daily_goal": settings.DailyScrobbleGoal = int.TryParse(value, out var dg) ? dg : 0; break;
                    case "excluded_artists": settings.ExcludedArtists = value ?? ""; break;
                    case "enable_diagnostic_log": settings.EnableDiagnosticLog = value == "1"; break;
                }
            }
            return settings;
        }
    }

    public void SaveSettings(AppSettings s)
    {
        lock (_lock)
        {
            void Set(string key, string? value) => Execute(
                "INSERT OR REPLACE INTO settings (key, value) VALUES (@k, @v)",
                ("@k", key), ("@v", value));

            Set("session_key", s.SessionKey);
            Set("username", s.Username);
            Set("scrobble_threshold_pct", s.ScrobbleThresholdPercent.ToString());
            Set("scrobble_threshold_max_s", s.ScrobbleThresholdMaxSeconds.ToString());
            Set("scrobble_min_s", s.ScrobbleMinSeconds.ToString());
            Set("auto_normalize", s.AutoNormalize ? "1" : "0");
            Set("filter_apple_music", s.FilterAppleMusicOnly ? "1" : "0");
            Set("edit_before_scrobble", s.EditBeforeScrobble ? "1" : "0");
            Set("start_with_windows", s.StartWithWindows ? "1" : "0");
            Set("show_now_playing_notif", s.ShowNowPlayingNotification ? "1" : "0");
            Set("duplicate_window_min", s.DuplicateWindowMinutes.ToString());
            Set("accent_color", s.AccentColor);
            Set("language", s.Language);
            Set("daily_goal", s.DailyScrobbleGoal.ToString());
            Set("excluded_artists", s.ExcludedArtists);
            Set("enable_diagnostic_log", s.EnableDiagnosticLog ? "1" : "0");
        }
    }

    // ── Normalization Rules ─────────────────────────────────────────────────

    public List<NormalizationRule> LoadRules()
    {
        lock (_lock)
        {
            var rules = new List<NormalizationRule>();
            using var cmd = _conn.CreateCommand();
            cmd.CommandText = "SELECT id, field, pattern, replacement, is_enabled, description, is_builtin, app_filter FROM normalization_rules ORDER BY id";
            using var r = cmd.ExecuteReader();
            while (r.Read())
            {
                rules.Add(new NormalizationRule
                {
                    Id = r.GetInt32(0),
                    Field = Enum.TryParse<RuleField>(r.GetString(1), true, out var f) ? f : RuleField.Title,
                    Pattern = r.GetString(2),
                    Replacement = r.GetString(3),
                    IsEnabled = r.GetInt32(4) == 1,
                    Description = r.GetString(5),
                    IsBuiltIn = r.GetInt32(6) == 1,
                    AppFilter = r.IsDBNull(7) ? "" : r.GetString(7)
                });
            }
            return rules;
        }
    }

    public void SaveRule(NormalizationRule rule)
    {
        lock (_lock)
        {
            if (rule.Id == 0)
            {
                Execute("INSERT INTO normalization_rules (field, pattern, replacement, is_enabled, description, is_builtin, app_filter) VALUES (@f, @p, @r, @e, @d, @b, @af)",
                    ("@f", rule.Field.ToString()), ("@p", rule.Pattern), ("@r", rule.Replacement),
                    ("@e", rule.IsEnabled ? "1" : "0"), ("@d", rule.Description), ("@b", rule.IsBuiltIn ? "1" : "0"),
                    ("@af", rule.AppFilter));
            }
            else
            {
                Execute("UPDATE normalization_rules SET field=@f, pattern=@p, replacement=@r, is_enabled=@e, description=@d, app_filter=@af WHERE id=@id",
                    ("@f", rule.Field.ToString()), ("@p", rule.Pattern), ("@r", rule.Replacement),
                    ("@e", rule.IsEnabled ? "1" : "0"), ("@d", rule.Description), ("@af", rule.AppFilter), ("@id", rule.Id.ToString()));
            }
        }
    }

    public void DeleteRule(int id)
    {
        lock (_lock) Execute("DELETE FROM normalization_rules WHERE id=@id AND is_builtin=0", ("@id", id.ToString()));
    }

    public void SetRuleEnabled(int id, bool enabled)
    {
        lock (_lock)
            Execute("UPDATE normalization_rules SET is_enabled=@e WHERE id=@id",
                ("@e", enabled ? "1" : "0"), ("@id", id.ToString()));
    }

    // ── Scrobble History ────────────────────────────────────────────────────

    public void AddScrobbleRecord(ScrobbleRecord record)
    {
        lock (_lock)
            Execute(@"INSERT INTO scrobble_history (title, artist, album, scrobbled_at, success, error_message)
                      VALUES (@t, @a, @al, @s, @ok, @err)",
                ("@t", record.Title), ("@a", record.Artist), ("@al", record.Album),
                ("@s", record.ScrobbledAt.ToString("O")),
                ("@ok", record.Success ? "1" : "0"),
                ("@err", record.ErrorMessage));
    }

    public List<ScrobbleRecord> LoadHistory(int limit = 200)
    {
        lock (_lock)
        {
            var list = new List<ScrobbleRecord>();
            using var cmd = _conn.CreateCommand();
            cmd.CommandText = "SELECT id, title, artist, album, scrobbled_at, success, error_message FROM scrobble_history ORDER BY id DESC LIMIT @lim";
            cmd.Parameters.AddWithValue("@lim", limit);
            using var r = cmd.ExecuteReader();
            while (r.Read())
            {
                list.Add(new ScrobbleRecord
                {
                    Id = r.GetInt32(0),
                    Title = r.GetString(1),
                    Artist = r.GetString(2),
                    Album = r.GetString(3),
                    ScrobbledAt = DateTime.Parse(r.GetString(4)),
                    Success = r.GetInt32(5) == 1,
                    ErrorMessage = r.IsDBNull(6) ? null : r.GetString(6)
                });
            }
            return list;
        }
    }

    public ScrobbleRecord? GetLastSuccessfulScrobble()
    {
        lock (_lock)
        {
            using var cmd = _conn.CreateCommand();
            cmd.CommandText = "SELECT id, title, artist, album, scrobbled_at, success, error_message FROM scrobble_history WHERE success=1 ORDER BY id DESC LIMIT 1";
            using var r = cmd.ExecuteReader();
            if (!r.Read()) return null;
            return new ScrobbleRecord
            {
                Id = r.GetInt32(0),
                Title = r.GetString(1),
                Artist = r.GetString(2),
                Album = r.GetString(3),
                ScrobbledAt = DateTime.Parse(r.GetString(4)),
                Success = true,
            };
        }
    }

    public bool WasRecentlyScrobbled(string artist, string title, int windowMinutes)
    {
        lock (_lock)
        {
            using var cmd = _conn.CreateCommand();
            // scrobbled_at is stored as an ISO "O" string (e.g. 2026-07-08T09:12:33.123Z) — comparing it
            // directly against datetime('now') (space-separated, no sub-second/us the 'T') as text made
            // any earlier-today scrobble count as "recent". Both sides must go through datetime() so SQLite
            // compares them as actual datetimes, not raw strings.
            cmd.CommandText = @"
                SELECT COUNT(*) FROM scrobble_history
                WHERE success=1
                  AND lower(artist)=lower(@a)
                  AND lower(title)=lower(@t)
                  AND datetime(scrobbled_at) >= datetime('now', @w)";
            cmd.Parameters.AddWithValue("@a", artist);
            cmd.Parameters.AddWithValue("@t", title);
            cmd.Parameters.AddWithValue("@w", $"-{windowMinutes} minutes");
            return (long)cmd.ExecuteScalar()! > 0;
        }
    }

    public (int total, int today, int thisWeek) GetStats()
    {
        lock (_lock)
        {
            var total = (int)Scalar<long>("SELECT COUNT(*) FROM scrobble_history WHERE success=1");

            // SQLite's date()/datetime() 'localtime' modifier returns NULL for some real-world
            // scrobbled_at values (7-digit fractional seconds + 'Z', seen on real user data) even
            // though the same string parses fine with no modifier at all. Compute the local-day
            // boundary in .NET instead and compare as plain UTC datetimes (no modifier involved).
            var startUtc = DateTime.Now.Date.ToUniversalTime();
            var endUtc = startUtc.AddDays(1);
            int today;
            using (var cmd = _conn.CreateCommand())
            {
                cmd.CommandText = @"
                    SELECT COUNT(*) FROM scrobble_history
                    WHERE success=1 AND datetime(scrobbled_at) >= datetime(@start) AND datetime(scrobbled_at) < datetime(@end)";
                cmd.Parameters.AddWithValue("@start", startUtc.ToString("O"));
                cmd.Parameters.AddWithValue("@end", endUtc.ToString("O"));
                today = (int)(long)cmd.ExecuteScalar()!;
            }

            var week = (int)Scalar<long>("SELECT COUNT(*) FROM scrobble_history WHERE success=1 AND datetime(scrobbled_at)>=datetime('now','-7 days')");
            return (total, today, week);
        }
    }

    public (string day, int count)[] GetDailyScrobbles(int days = 14)
    {
        lock (_lock)
        {
            // Grouping done in .NET, not via SQLite's date(...,'localtime') — see GetStats for why.
            using var cmd = _conn.CreateCommand();
            cmd.CommandText = @"
                SELECT scrobbled_at FROM scrobble_history
                WHERE success=1 AND datetime(scrobbled_at) >= datetime('now', @days)";
            cmd.Parameters.AddWithValue("@days", $"-{days} days");
            var counts = new SortedDictionary<string, int>(StringComparer.Ordinal);
            using (var r = cmd.ExecuteReader())
            {
                while (r.Read())
                {
                    if (!TryParseUtc(r.GetString(0), out var utc)) continue;
                    var localDay = utc.ToLocalTime().ToString("yyyy-MM-dd");
                    counts.TryGetValue(localDay, out var c);
                    counts[localDay] = c + 1;
                }
            }
            return counts.Select(kv => (kv.Key, kv.Value)).ToArray();
        }
    }

    public (string artist, int count)[] GetTopArtists(int limit = 8)
    {
        lock (_lock)
        {
            var list = new List<(string, int)>();
            using var cmd = _conn.CreateCommand();
            cmd.CommandText = @"
                SELECT artist, COUNT(*) as cnt
                FROM scrobble_history
                WHERE success=1
                GROUP BY lower(artist)
                ORDER BY cnt DESC LIMIT @lim";
            cmd.Parameters.AddWithValue("@lim", limit);
            using var r = cmd.ExecuteReader();
            while (r.Read()) list.Add((r.GetString(0), r.GetInt32(1)));
            return list.ToArray();
        }
    }

    public (string artist, string title, int count)[] GetTopTracks(int limit = 8)
    {
        lock (_lock)
        {
            var list = new List<(string, string, int)>();
            using var cmd = _conn.CreateCommand();
            cmd.CommandText = @"
                SELECT artist, title, COUNT(*) as cnt
                FROM scrobble_history
                WHERE success=1
                GROUP BY lower(artist), lower(title)
                ORDER BY cnt DESC LIMIT @lim";
            cmd.Parameters.AddWithValue("@lim", limit);
            using var r = cmd.ExecuteReader();
            while (r.Read()) list.Add((r.GetString(0), r.GetString(1), r.GetInt32(2)));
            return list.ToArray();
        }
    }

    public void UpdateScrobbleRecord(int id, string artist, string title, string album)
    {
        lock (_lock)
            Execute("UPDATE scrobble_history SET artist=@a, title=@t, album=@al WHERE id=@id",
                ("@a", artist), ("@t", title), ("@al", album), ("@id", id.ToString()));
    }

    public int GetCurrentStreak()
    {
        lock (_lock)
        {
            // Local-day grouping done in .NET — see GetStats for why the SQLite 'localtime'
            // modifier isn't used here.
            using var cmd = _conn.CreateCommand();
            cmd.CommandText = "SELECT scrobbled_at FROM scrobble_history WHERE success=1";
            var dayset = new HashSet<DateTime>();
            using (var r = cmd.ExecuteReader())
            {
                while (r.Read())
                {
                    if (TryParseUtc(r.GetString(0), out var utc)) dayset.Add(utc.ToLocalTime().Date);
                }
            }
            if (dayset.Count == 0) return 0;
            var days = dayset.OrderByDescending(d => d).ToList();
            if ((DateTime.Today - days[0]).TotalDays >= 2) return 0;
            int streak = 0;
            var expected = days[0];
            foreach (var day in days)
            {
                if (day == expected) { streak++; expected = expected.AddDays(-1); }
                else break;
            }
            return streak;
        }
    }

    private static bool TryParseUtc(string s, out DateTime utc)
    {
        // ScrobbledAt is always written as DateTime.UtcNow.ToString("O"), which includes a
        // trailing 'Z' — RoundtripKind alone is enough for DateTime.Parse to recognize that as UTC.
        if (!DateTime.TryParse(s, System.Globalization.CultureInfo.InvariantCulture,
                System.Globalization.DateTimeStyles.RoundtripKind, out utc))
            return false;
        if (utc.Kind == DateTimeKind.Unspecified) utc = DateTime.SpecifyKind(utc, DateTimeKind.Utc);
        return true;
    }

    public void ExportToCsv(string path)
    {
        lock (_lock)
        {
            using var cmd = _conn.CreateCommand();
            cmd.CommandText = "SELECT artist, title, album, scrobbled_at FROM scrobble_history WHERE success=1 ORDER BY scrobbled_at DESC";
            using var r = cmd.ExecuteReader();
            using var w = new System.IO.StreamWriter(path, false, System.Text.Encoding.UTF8);
            w.WriteLine("Artist,Title,Album,ScrobbledAt");
            while (r.Read())
                w.WriteLine($"\"{Esc(r.GetString(0))}\",\"{Esc(r.GetString(1))}\",\"{Esc(r.GetString(2))}\",\"{r.GetString(3)}\"");
            static string Esc(string s) => s.Replace("\"", "\"\"");
        }
    }

    public int ImportFromCsv(string path)
    {
        lock (_lock)
        {
            var lines = System.IO.File.ReadAllLines(path, System.Text.Encoding.UTF8);
            int imported = 0;
            foreach (var line in lines.Skip(1))
            {
                var parts = ParseCsvLine(line);
                if (parts.Length < 4) continue;
                try
                {
                    var at = DateTime.Parse(parts[3]);
                    using var chk = _conn.CreateCommand();
                    chk.CommandText = "SELECT COUNT(*) FROM scrobble_history WHERE lower(artist)=lower(@a) AND lower(title)=lower(@t) AND scrobbled_at=@s";
                    chk.Parameters.AddWithValue("@a", parts[0]);
                    chk.Parameters.AddWithValue("@t", parts[1]);
                    chk.Parameters.AddWithValue("@s", at.ToString("O"));
                    if ((long)chk.ExecuteScalar()! > 0) continue;
                    Execute("INSERT INTO scrobble_history (artist, title, album, scrobbled_at, success) VALUES (@a, @t, @al, @s, 1)",
                        ("@a", parts[0]), ("@t", parts[1]), ("@al", parts[2]), ("@s", at.ToString("O")));
                    imported++;
                }
                catch { }
            }
            return imported;
        }
    }

    private static string[] ParseCsvLine(string line)
    {
        var parts = new List<string>();
        bool inQ = false;
        var cur = new System.Text.StringBuilder();
        for (int i = 0; i < line.Length; i++)
        {
            char c = line[i];
            if (c == '"') { if (inQ && i + 1 < line.Length && line[i + 1] == '"') { cur.Append('"'); i++; } else inQ = !inQ; }
            else if (c == ',' && !inQ) { parts.Add(cur.ToString()); cur.Clear(); }
            else cur.Append(c);
        }
        parts.Add(cur.ToString());
        return parts.ToArray();
    }

    // ── Pending Queue ───────────────────────────────────────────────────────

    public void AddPendingScrobble(PendingScrobble p)
    {
        lock (_lock)
            Execute(@"INSERT INTO pending_scrobbles (title, artist, album, played_at, queued_at)
                      VALUES (@t, @a, @al, @p, @q)",
                ("@t", p.Title), ("@a", p.Artist), ("@al", p.Album),
                ("@p", p.PlayedAt.ToString("O")),
                ("@q", p.QueuedAt.ToString("O")));
    }

    public List<PendingScrobble> LoadPendingScrobbles()
    {
        lock (_lock)
        {
            var list = new List<PendingScrobble>();
            using var cmd = _conn.CreateCommand();
            cmd.CommandText = "SELECT id, title, artist, album, played_at, queued_at FROM pending_scrobbles ORDER BY id LIMIT 50";
            using var r = cmd.ExecuteReader();
            while (r.Read())
            {
                list.Add(new PendingScrobble
                {
                    Id = r.GetInt32(0),
                    Title = r.GetString(1),
                    Artist = r.GetString(2),
                    Album = r.GetString(3),
                    PlayedAt = DateTime.Parse(r.GetString(4)),
                    QueuedAt = DateTime.Parse(r.GetString(5)),
                });
            }
            return list;
        }
    }

    public void DeletePendingScrobble(int id)
    {
        lock (_lock) Execute("DELETE FROM pending_scrobbles WHERE id=@id", ("@id", id.ToString()));
    }

    public int PendingCount()
    {
        lock (_lock) return (int)Scalar<long>("SELECT COUNT(*) FROM pending_scrobbles");
    }

    // ── Helpers ─────────────────────────────────────────────────────────────

    private void SeedDefaultRules()
    {
        foreach (var rule in NormalizationRule.GetDefaults())
            SaveRule(rule);
    }

    private void Execute(string sql, params (string name, string? value)[] parameters)
    {
        using var cmd = _conn.CreateCommand();
        cmd.CommandText = sql;
        foreach (var (name, value) in parameters)
            cmd.Parameters.AddWithValue(name, (object?)value ?? DBNull.Value);
        cmd.ExecuteNonQuery();
    }

    private T Scalar<T>(string sql)
    {
        using var cmd = _conn.CreateCommand();
        cmd.CommandText = sql;
        return (T)cmd.ExecuteScalar()!;
    }

    public void Dispose() => _conn.Dispose();
}
