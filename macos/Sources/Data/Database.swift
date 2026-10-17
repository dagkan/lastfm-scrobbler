import Foundation
import SQLite3

final class Database: @unchecked Sendable {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.dagkan.lastfm-scrobbler.db", qos: .utility)

    init(path: String) {
        sqlite3_open(path, &db)
        migrate()
    }

    deinit { sqlite3_close(db) }

    // MARK: - Migration

    private func migrate() {
        execute("""
            CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value TEXT
            )
        """)
        execute("""
            CREATE TABLE IF NOT EXISTS normalization_rules (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                field TEXT NOT NULL,
                pattern TEXT NOT NULL,
                replacement TEXT NOT NULL,
                is_enabled INTEGER NOT NULL DEFAULT 1,
                description TEXT,
                is_builtin INTEGER NOT NULL DEFAULT 0
            )
        """)
        execute("""
            CREATE TABLE IF NOT EXISTS scrobble_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                artist TEXT NOT NULL,
                album TEXT,
                scrobbled_at TEXT NOT NULL,
                success INTEGER NOT NULL DEFAULT 1,
                error_message TEXT
            )
        """)
        execute("""
            CREATE TABLE IF NOT EXISTS pending_scrobbles (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                artist TEXT NOT NULL,
                album TEXT,
                played_at TEXT NOT NULL,
                queued_at TEXT NOT NULL
            )
        """)

        if scalar("SELECT COUNT(*) FROM normalization_rules WHERE is_builtin = 1") == 0 {
            for rule in NormalizationRule.getDefaults() {
                execute("""
                    INSERT INTO normalization_rules (field, pattern, replacement, is_enabled, description, is_builtin)
                    VALUES (?, ?, ?, ?, ?, 1)
                """, params: rule.field.rawValue, rule.pattern, rule.replacement,
                        rule.isEnabled ? 1 : 0, rule.description)
            }
        }
    }

    // MARK: - Settings

    func loadSettings() -> AppSettings {
        var s = AppSettings()
        s.sessionKey = string("SELECT value FROM settings WHERE key='session_key'") ?? ""
        s.username = string("SELECT value FROM settings WHERE key='username'") ?? ""
        s.scrobbleThresholdPercent = int("SELECT value FROM settings WHERE key='threshold_percent'") ?? 50
        s.scrobbleThresholdMaxSeconds = int("SELECT value FROM settings WHERE key='threshold_max_seconds'") ?? 240
        s.scrobbleMinSeconds = int("SELECT value FROM settings WHERE key='min_seconds'") ?? 30
        s.autoNormalize = bool("SELECT value FROM settings WHERE key='auto_normalize'") ?? true
        s.filterAppleMusicOnly = bool("SELECT value FROM settings WHERE key='filter_apple_music'") ?? true
        s.editBeforeScrobble = bool("SELECT value FROM settings WHERE key='edit_before_scrobble'") ?? false
        s.startAtLogin = bool("SELECT value FROM settings WHERE key='start_at_login'") ?? false
        s.showNowPlayingNotification = bool("SELECT value FROM settings WHERE key='show_notification'") ?? false
        s.duplicateWindowMinutes = int("SELECT value FROM settings WHERE key='duplicate_window'") ?? 5
        s.accentColor = string("SELECT value FROM settings WHERE key='accent_color'") ?? "#BA0000"
        s.language = string("SELECT value FROM settings WHERE key='language'") ?? "en"
        s.dailyScrobbleGoal = int("SELECT value FROM settings WHERE key='daily_goal'") ?? 0
        s.webhookUrl = string("SELECT value FROM settings WHERE key='webhook_url'") ?? ""
        s.webhookOnScrobble = bool("SELECT value FROM settings WHERE key='webhook_on_scrobble'") ?? true
        s.webhookOnNowPlaying = bool("SELECT value FROM settings WHERE key='webhook_on_now_playing'") ?? false
        s.telemetryEnabled = bool("SELECT value FROM settings WHERE key='telemetry_enabled'") ?? true
        s.installId = string("SELECT value FROM settings WHERE key='install_id'") ?? ""
        s.enableGlobalHotkeys = bool("SELECT value FROM settings WHERE key='enable_global_hotkeys'") ?? false
        return s
    }

    func saveSettings(_ s: AppSettings) {
        func set(_ key: String, _ value: String) {
            execute("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)", params: key, value)
        }
        set("session_key", s.sessionKey)
        set("username", s.username)
        set("threshold_percent", "\(s.scrobbleThresholdPercent)")
        set("threshold_max_seconds", "\(s.scrobbleThresholdMaxSeconds)")
        set("min_seconds", "\(s.scrobbleMinSeconds)")
        set("auto_normalize", s.autoNormalize ? "1" : "0")
        set("filter_apple_music", s.filterAppleMusicOnly ? "1" : "0")
        set("edit_before_scrobble", s.editBeforeScrobble ? "1" : "0")
        set("start_at_login", s.startAtLogin ? "1" : "0")
        set("show_notification", s.showNowPlayingNotification ? "1" : "0")
        set("duplicate_window", "\(s.duplicateWindowMinutes)")
        set("accent_color", s.accentColor)
        set("language", s.language)
        set("daily_goal", "\(s.dailyScrobbleGoal)")
        set("webhook_url", s.webhookUrl)
        set("webhook_on_scrobble", s.webhookOnScrobble ? "1" : "0")
        set("webhook_on_now_playing", s.webhookOnNowPlaying ? "1" : "0")
        set("telemetry_enabled", s.telemetryEnabled ? "1" : "0")
        set("install_id", s.installId)
        set("enable_global_hotkeys", s.enableGlobalHotkeys ? "1" : "0")
    }

    // MARK: - Normalization Rules

    func loadRules() -> [NormalizationRule] {
        var rules: [NormalizationRule] = []
        query("SELECT id, field, pattern, replacement, is_enabled, description, is_builtin FROM normalization_rules") { stmt in
            let id = sqlite3_column_int64(stmt, 0)
            let field = NormalizationField(rawValue: col(stmt, 1) ?? "Title") ?? .title
            let pattern = col(stmt, 2) ?? ""
            let replacement = col(stmt, 3) ?? ""
            let isEnabled = sqlite3_column_int(stmt, 4) != 0
            let description = col(stmt, 5) ?? ""
            let isBuiltIn = sqlite3_column_int(stmt, 6) != 0
            rules.append(NormalizationRule(id: id, field: field, pattern: pattern, replacement: replacement,
                                           isEnabled: isEnabled, description: description, isBuiltIn: isBuiltIn))
        }
        return rules
    }

    func saveRule(_ rule: NormalizationRule) {
        if rule.id <= 0 {
            execute("INSERT INTO normalization_rules (field, pattern, replacement, is_enabled, description, is_builtin) VALUES (?, ?, ?, ?, ?, 0)",
                    params: rule.field.rawValue, rule.pattern, rule.replacement, rule.isEnabled ? 1 : 0, rule.description)
        } else {
            execute("UPDATE normalization_rules SET field=?, pattern=?, replacement=?, is_enabled=?, description=? WHERE id=?",
                    params: rule.field.rawValue, rule.pattern, rule.replacement, rule.isEnabled ? 1 : 0, rule.description, rule.id)
        }
    }

    func deleteRule(id: Int64) {
        execute("DELETE FROM normalization_rules WHERE id=? AND is_builtin=0", params: id)
    }

    func setRuleEnabled(id: Int64, enabled: Bool) {
        execute("UPDATE normalization_rules SET is_enabled=? WHERE id=?", params: enabled ? 1 : 0, id)
    }

    // MARK: - Scrobble History

    func addScrobbleRecord(_ record: ScrobbleRecord) {
        execute("INSERT INTO scrobble_history (title, artist, album, scrobbled_at, success, error_message) VALUES (?, ?, ?, ?, ?, ?)",
                params: record.title, record.artist, record.album,
                ISO8601DateFormatter().string(from: record.scrobbledAt),
                record.success ? 1 : 0, record.errorMessage ?? "")
    }

    func loadHistory(limit: Int = 200) -> [ScrobbleRecord] {
        let iso = ISO8601DateFormatter()
        var records: [ScrobbleRecord] = []
        query("SELECT id, title, artist, album, scrobbled_at, success, error_message FROM scrobble_history ORDER BY scrobbled_at DESC LIMIT ?", params: limit) { stmt in
            let id = sqlite3_column_int64(stmt, 0)
            let title = col(stmt, 1) ?? ""
            let artist = col(stmt, 2) ?? ""
            let album = col(stmt, 3) ?? ""
            let dateStr = col(stmt, 4) ?? ""
            let success = sqlite3_column_int(stmt, 5) != 0
            let error = col(stmt, 6)
            let date = iso.date(from: dateStr) ?? Date()
            records.append(ScrobbleRecord(id: id, title: title, artist: artist, album: album,
                                          scrobbledAt: date, success: success, errorMessage: error))
        }
        return records
    }

    func wasRecentlyScrobbled(artist: String, title: String, windowMinutes: Int) -> Bool {
        let cutoff = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-Double(windowMinutes * 60)))
        let count: Int = scalar("SELECT COUNT(*) FROM scrobble_history WHERE LOWER(artist)=LOWER(?) AND LOWER(title)=LOWER(?) AND scrobbled_at > ? AND success=1",
                                params: artist, title, cutoff)
        return count > 0
    }

    func updateScrobbleRecord(id: Int64, artist: String, title: String, album: String) {
        execute("UPDATE scrobble_history SET artist=?, title=?, album=? WHERE id=?", params: artist, title, album, id)
    }

    func getStats() -> (total: Int, today: Int, thisWeek: Int) {
        let total: Int = scalar("SELECT COUNT(*) FROM scrobble_history WHERE success=1")
        let todayStr = Calendar.current.startOfDay(for: Date())
        let todayISO = ISO8601DateFormatter().string(from: todayStr)
        let today: Int = scalar("SELECT COUNT(*) FROM scrobble_history WHERE success=1 AND scrobbled_at >= ?", params: todayISO)
        let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let weekISO = ISO8601DateFormatter().string(from: weekStart)
        let week: Int = scalar("SELECT COUNT(*) FROM scrobble_history WHERE success=1 AND scrobbled_at >= ?", params: weekISO)
        return (total, today, week)
    }

    func getDailyScrobbles(days: Int) -> [(date: String, count: Int)] {
        var result: [(String, Int)] = []
        query("SELECT DATE(scrobbled_at) as d, COUNT(*) as c FROM scrobble_history WHERE success=1 AND scrobbled_at >= DATE('now', '-\(days) days') GROUP BY d ORDER BY d ASC") { stmt in
            let d = col(stmt, 0) ?? ""
            let c = Int(sqlite3_column_int(stmt, 1))
            result.append((d, c))
        }
        return result
    }

    func getTopArtists(limit: Int = 10) -> [(artist: String, count: Int)] {
        var result: [(String, Int)] = []
        query("SELECT LOWER(artist) as a, COUNT(*) as c FROM scrobble_history WHERE success=1 GROUP BY a ORDER BY c DESC LIMIT ?", params: limit) { stmt in
            result.append((col(stmt, 0) ?? "", Int(sqlite3_column_int(stmt, 1))))
        }
        return result
    }

    func getTopTracks(limit: Int = 10) -> [(title: String, artist: String, count: Int)] {
        var result: [(String, String, Int)] = []
        query("SELECT title, artist, COUNT(*) as c FROM scrobble_history WHERE success=1 GROUP BY LOWER(title), LOWER(artist) ORDER BY c DESC LIMIT ?", params: limit) { stmt in
            result.append((col(stmt, 0) ?? "", col(stmt, 1) ?? "", Int(sqlite3_column_int(stmt, 2))))
        }
        return result
    }

    func getCurrentStreak() -> Int {
        var streak = 0
        var checkDate = Calendar.current.startOfDay(for: Date())
        let iso = ISO8601DateFormatter()
        while true {
            let start = iso.string(from: checkDate)
            let end = iso.string(from: checkDate.addingTimeInterval(86400))
            let count: Int = scalar("SELECT COUNT(*) FROM scrobble_history WHERE success=1 AND scrobbled_at >= ? AND scrobbled_at < ?",
                                    params: start, end)
            if count == 0 { break }
            streak += 1
            checkDate = checkDate.addingTimeInterval(-86400)
        }
        return streak
    }

    // MARK: - Pending Queue

    func addPendingScrobble(_ s: PendingScrobble) {
        let iso = ISO8601DateFormatter()
        execute("INSERT INTO pending_scrobbles (title, artist, album, played_at, queued_at) VALUES (?, ?, ?, ?, ?)",
                params: s.title, s.artist, s.album, iso.string(from: s.playedAt), iso.string(from: s.queuedAt))
    }

    func loadPendingScrobbles(limit: Int = 50) -> [PendingScrobble] {
        let iso = ISO8601DateFormatter()
        var result: [PendingScrobble] = []
        query("SELECT id, title, artist, album, played_at, queued_at FROM pending_scrobbles ORDER BY queued_at ASC LIMIT ?", params: limit) { stmt in
            let id = sqlite3_column_int64(stmt, 0)
            let title = col(stmt, 1) ?? ""
            let artist = col(stmt, 2) ?? ""
            let album = col(stmt, 3) ?? ""
            let playedAt = iso.date(from: col(stmt, 4) ?? "") ?? Date()
            let queuedAt = iso.date(from: col(stmt, 5) ?? "") ?? Date()
            result.append(PendingScrobble(id: id, title: title, artist: artist, album: album,
                                          playedAt: playedAt, queuedAt: queuedAt))
        }
        return result
    }

    func deletePendingScrobble(id: Int64) {
        execute("DELETE FROM pending_scrobbles WHERE id=?", params: id)
    }

    func pendingCount() -> Int {
        scalar("SELECT COUNT(*) FROM pending_scrobbles")
    }

    // MARK: - CSV

    func exportToCSV(path: String) throws {
        let records = loadHistory(limit: Int.max)
        var lines = ["\"Time\",\"Artist\",\"Title\",\"Album\",\"Status\""]
        let iso = ISO8601DateFormatter()
        for r in records {
            func q(_ s: String) -> String { "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            lines.append("\(q(iso.string(from: r.scrobbledAt))),\(q(r.artist)),\(q(r.title)),\(q(r.album)),\(r.success ? "OK" : "Failed")")
        }
        try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    func importFromCSV(path: String) throws -> (imported: Int, skipped: Int) {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.components(separatedBy: "\n").dropFirst()
        var imported = 0, skipped = 0
        let iso = ISO8601DateFormatter()
        for line in lines {
            let cols = parseCSVLine(line)
            guard cols.count >= 4, let date = iso.date(from: cols[0]) else { continue }
            let artist = cols[1], title = cols[2], album = cols[3]
            let exists: Int = scalar("SELECT COUNT(*) FROM scrobble_history WHERE LOWER(artist)=LOWER(?) AND LOWER(title)=LOWER(?) AND scrobbled_at=?",
                                     params: artist, title, iso.string(from: date))
            if exists > 0 { skipped += 1; continue }
            let record = ScrobbleRecord(id: 0, title: title, artist: artist, album: album,
                                        scrobbledAt: date, success: true, errorMessage: nil)
            addScrobbleRecord(record)
            imported += 1
        }
        return (imported, skipped)
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if c == "\"" {
                let next = line.index(after: i)
                if inQuotes && next < line.endIndex && line[next] == "\"" {
                    current.append("\""); i = line.index(after: next); continue
                }
                inQuotes.toggle()
            } else if c == "," && !inQuotes {
                fields.append(current); current = ""
            } else {
                current.append(c)
            }
            i = line.index(after: i)
        }
        fields.append(current)
        return fields
    }

    // MARK: - Helpers

    private func execute(_ sql: String, params: Any...) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, params)
        sqlite3_step(stmt)
    }

    private func query(_ sql: String, params: Any..., row: (OpaquePointer?) -> Void) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, params)
        while sqlite3_step(stmt) == SQLITE_ROW { row(stmt) }
    }

    private func scalar<T: BinaryInteger>(_ sql: String, params: Any...) -> T {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, params)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return T(sqlite3_column_int64(stmt, 0))
    }

    private func string(_ sql: String, params: Any...) -> String? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, params)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return col(stmt, 0)
    }

    private func int(_ sql: String, params: Any...) -> Int? {
        guard let s = string(sql, params: params) else { return nil }
        return Int(s)
    }

    private func bool(_ sql: String, params: Any...) -> Bool? {
        guard let s = string(sql, params: params) else { return nil }
        return s == "1"
    }

    private func col(_ stmt: OpaquePointer?, _ i: Int32) -> String? {
        guard let p = sqlite3_column_text(stmt, i) else { return nil }
        return String(cString: p)
    }

    private func bind(_ stmt: OpaquePointer?, _ params: [Any]) {
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case let v as String: sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            case let v as Int: sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Int64: sqlite3_bind_int64(stmt, idx, v)
            default: sqlite3_bind_null(stmt, idx)
            }
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
