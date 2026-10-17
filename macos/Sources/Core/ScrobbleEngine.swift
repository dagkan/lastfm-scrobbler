import Foundation
import AppKit
import UserNotifications

struct LogEntry: Identifiable, Sendable {
    enum Kind: Sendable { case nowPlaying, scrobbled, loved, unloved, failed, manual, queueFlushed }
    let id = UUID()
    let kind: Kind
    let text: String
    let timestamp: Date
}

@MainActor
final class ScrobbleEngine: ObservableObject {
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying = false
    /// 0…1 — share of the scrobble threshold reached (not of the track length).
    @Published private(set) var scrobbleProgress: Double = 0
    /// Accumulated listening time for the current track, seconds.
    @Published private(set) var playedSeconds: Int = 0
    @Published private(set) var logs: [LogEntry] = []
    @Published private(set) var sessionScrobbleCount = 0
    @Published private(set) var pendingCount = 0

    var onEditBeforeScrobble: ((Track) async -> Track?)? = nil

    private let db: Database
    private var settings: AppSettings
    private let lastFm: LastFmClient
    private let watcher: MediaWatcher
    private let webhook: WebhookClient
    private var normalizer: TrackNormalizer

    private var progressTask: Task<Void, Never>?
    private var queueRetryTimer: Task<Void, Never>?
    private var trackStartTime: Date?
    private var lastScrobbledTrack: Track?

    // Accumulated-listen-time model (mirrors the Windows engine): the countdown
    // only advances while Apple Music reports "Playing", so a pause freezes it
    // instead of a wall-clock timer firing regardless. Measured on the monotonic
    // uptime clock — a wall-clock step backwards must never produce a negative delta.
    private var playedMs: Int = 0
    private var thresholdMs: Int = 0
    private var lastTickUptime: TimeInterval = 0
    private var scrobbledCurrent = false
    private var trackGeneration = 0

    init(db: Database, settings: AppSettings) {
        self.db = db
        self.settings = settings
        self.lastFm = LastFmClient()
        self.watcher = MediaWatcher(filterAppleMusicOnly: settings.filterAppleMusicOnly)
        self.webhook = WebhookClient()
        self.normalizer = TrackNormalizer(rules: db.loadRules())
    }

    func start() async {
        await lastFm.setSessionKey(settings.sessionKey)
        watcher.onTrackChanged = { [weak self] track in
            guard let self else { return }
            Task { @MainActor in await self.onTrackChanged(track) }
        }
        watcher.onPlaybackPaused = { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.handlePaused() }
        }
        watcher.onPlaybackStopped = { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.handleStopped() }
        }
        watcher.start()
        pendingCount = db.pendingCount()
        startQueueRetry()
        startProgressLoop()
        await flushPendingQueue()
    }

    func stop() { watcher.stop(); queueRetryTimer?.cancel(); progressTask?.cancel() }

    func applySettings(_ newSettings: AppSettings) {
        settings = newSettings
        Task { await lastFm.setSessionKey(newSettings.sessionKey) }
        normalizer = TrackNormalizer(rules: db.loadRules())
    }

    func reloadRules() {
        normalizer = TrackNormalizer(rules: db.loadRules())
    }

    // MARK: - Track Changed

    private func onTrackChanged(_ raw: Track?) async {
        guard let raw, raw.isValid else { handleStopped(); return }

        var track = settings.autoNormalize ? normalizer.normalize(raw) : raw

        if let current = currentTrack, current.isSameTrack(track) {
            // Apple Music re-sends playerInfo for the same track on resume and on
            // metadata nudges. Resume just restarts the clock; a fresh listen after
            // the track was already scrobbled (repeat / replay) is a new generation.
            if !scrobbledCurrent {
                isPlaying = true
                lastTickUptime = ProcessInfo.processInfo.systemUptime
                return
            }
        }

        if track.album.isEmpty, let resolved = try? await lastFm.getAlbumName(artist: track.artist, title: track.title) {
            track.album = resolved
        }

        trackGeneration += 1
        currentTrack = track
        isPlaying = true
        trackStartTime = Date()
        playedMs = 0
        playedSeconds = 0
        thresholdMs = calculateThresholdMs(track)
        scrobbledCurrent = false
        scrobbleProgress = 0
        lastTickUptime = ProcessInfo.processInfo.systemUptime

        addLog(.nowPlaying, "\(track.artist) – \(track.title)")
        try? await lastFm.updateNowPlaying(track: track)

        if !settings.webhookUrl.isEmpty && settings.webhookOnNowPlaying {
            webhook.post(url: settings.webhookUrl, event: "now_playing", track: track, success: true)
        }

        if settings.showNowPlayingNotification {
            sendNotification(title: "Now Playing", body: "\(track.artist) – \(track.title)")
        }
    }

    private func handlePaused() {
        // Keep the track and the accumulated time; just stop counting.
        isPlaying = false
    }

    private func handleStopped() {
        isPlaying = false
        scrobbleProgress = 0
        playedSeconds = 0
        currentTrack = nil
        if !settings.webhookUrl.isEmpty && settings.webhookOnNowPlaying {
            webhook.post(url: settings.webhookUrl, event: "stopped", track: nil, success: true)
        }
    }

    // MARK: - Scrobble Timing

    private func calculateThresholdMs(_ track: Track) -> Int {
        let minMs = settings.scrobbleMinSeconds * 1000
        let maxMs = settings.scrobbleThresholdMaxSeconds * 1000
        guard track.durationSeconds > 0 else {
            return max(minMs, Int(Double(maxMs) * Double(settings.scrobbleThresholdPercent) / 100.0))
        }
        var byPercent = Int(Double(track.durationSeconds) * 1000 * Double(settings.scrobbleThresholdPercent) / 100.0)
        // Never schedule at/after the track's natural end — the next track is
        // usually already playing by then and the scrobble silently drops.
        byPercent = min(byPercent, max(0, track.durationSeconds * 1000 - 5000))
        return max(minMs, min(byPercent, maxMs))
    }

    private func startProgressLoop() {
        progressTask?.cancel()
        lastTickUptime = ProcessInfo.processInfo.systemUptime
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self else { return }
                await self.tick()
            }
        }
    }

    private func tick() async {
        let now = ProcessInfo.processInfo.systemUptime
        let deltaMs = min(max(Int((now - lastTickUptime) * 1000), 0), 2000)
        lastTickUptime = now

        guard let track = currentTrack, !scrobbledCurrent else { return }
        if isPlaying { playedMs += deltaMs }

        playedSeconds = playedMs / 1000
        scrobbleProgress = thresholdMs > 0 ? min(Double(playedMs) / Double(thresholdMs), 1.0) : 0

        if thresholdMs > 0, playedMs >= thresholdMs {
            scrobbledCurrent = true
            let gen = trackGeneration
            await doScrobble(track: track, generation: gen)
        }
    }

    private func doScrobble(track: Track, generation: Int) async {
        guard generation == trackGeneration, currentTrack?.isSameTrack(track) == true else { return }
        if db.wasRecentlyScrobbled(artist: track.artist, title: track.title, windowMinutes: settings.duplicateWindowMinutes) {
            addLog(.scrobbled, "Duplicate skipped: \(track.artist) – \(track.title)")
            return
        }

        var finalTrack = track
        if settings.editBeforeScrobble, let edited = await onEditBeforeScrobble?(track) {
            finalTrack = edited
        }

        let playedAt = trackStartTime ?? Date()
        do {
            try await lastFm.scrobble(track: finalTrack, timestamp: playedAt)
            let record = ScrobbleRecord(id: 0, title: finalTrack.title, artist: finalTrack.artist,
                                        album: finalTrack.album, scrobbledAt: Date(), success: true, errorMessage: nil)
            db.addScrobbleRecord(record)
            sessionScrobbleCount += 1
            addLog(.scrobbled, "\(finalTrack.artist) – \(finalTrack.title)")
            lastScrobbledTrack = finalTrack
            Telemetry.scrobble(1)

            if !settings.webhookUrl.isEmpty && settings.webhookOnScrobble {
                webhook.post(url: settings.webhookUrl, event: "scrobbled", track: finalTrack, success: true)
            }
        } catch {
            let record = ScrobbleRecord(id: 0, title: finalTrack.title, artist: finalTrack.artist,
                                        album: finalTrack.album, scrobbledAt: Date(), success: false, errorMessage: error.localizedDescription)
            db.addScrobbleRecord(record)
            let pending = PendingScrobble(id: 0, title: finalTrack.title, artist: finalTrack.artist,
                                          album: finalTrack.album, playedAt: playedAt, queuedAt: Date())
            db.addPendingScrobble(pending)
            pendingCount = db.pendingCount()
            addLog(.failed, "\(finalTrack.artist) – \(finalTrack.title): \(error.localizedDescription)")
        }
    }

    // MARK: - Manual Scrobble

    func manualScrobble(title: String, artist: String, album: String, timestamp: Date) async {
        let track = Track(title: title, artist: artist, album: album, albumArtist: artist,
                          durationSeconds: 0, trackNumber: 0, detectedAt: Date(), sourceApp: "Manual")
        do {
            try await lastFm.scrobble(track: track, timestamp: timestamp)
            let record = ScrobbleRecord(id: 0, title: title, artist: artist, album: album,
                                        scrobbledAt: Date(), success: true, errorMessage: nil)
            db.addScrobbleRecord(record)
            sessionScrobbleCount += 1
            Telemetry.scrobble(1)
            addLog(.manual, "Manual: \(artist) – \(title)")
        } catch {
            addLog(.failed, "Manual failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Love / Unlove

    func loveTrack() async {
        guard let track = currentTrack ?? lastScrobbledTrack else { return }
        do {
            try await lastFm.loveTrack(artist: track.artist, title: track.title)
            addLog(.loved, "\(track.artist) – \(track.title)")
        } catch {
            addLog(.failed, "Love failed: \(error.localizedDescription)")
        }
    }

    func unloveTrack() async {
        guard let track = currentTrack ?? lastScrobbledTrack else { return }
        do {
            try await lastFm.unloveTrack(artist: track.artist, title: track.title)
            addLog(.unloved, "\(track.artist) – \(track.title)")
        } catch {
            addLog(.failed, "Unlove failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Queue Flush

    private func startQueueRetry() {
        queueRetryTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000_000) // 5 min
                guard !Task.isCancelled, let self else { return }
                await self.flushPendingQueue()
            }
        }
    }

    func flushPendingQueue() async {
        let pending = db.loadPendingScrobbles(limit: 50)
        guard !pending.isEmpty else { return }
        var flushed = 0
        for item in pending {
            let t = Track(title: item.title, artist: item.artist, album: item.album, albumArtist: item.artist,
                          durationSeconds: 0, trackNumber: 0, detectedAt: item.playedAt, sourceApp: "Apple Music")
            do {
                try await lastFm.scrobble(track: t, timestamp: item.playedAt)
                db.deletePendingScrobble(id: item.id)
                flushed += 1
            } catch { break }
        }
        if flushed > 0 {
            pendingCount = db.pendingCount()
            Telemetry.scrobble(flushed)
            addLog(.queueFlushed, "Flushed \(flushed) queued scrobble\(flushed == 1 ? "" : "s")")
        }
    }

    // MARK: - Helpers

    func getArtistInfo(artist: String) async throws -> ArtistInfo {
        try await lastFm.getArtistInfo(artist: artist)
    }

    func getArtistTopTags(artist: String) async throws -> [String] {
        try await lastFm.getArtistTopTags(artist: artist)
    }

    func getUserInfo() async throws -> UserInfo {
        try await lastFm.getUserInfo()
    }

    func getUserTopArtists(period: String) async throws -> [TopItem] {
        try await lastFm.getUserTopArtists(period: period)
    }

    func getUserTopTracks(period: String) async throws -> [TopItem] {
        try await lastFm.getUserTopTracks(period: period)
    }

    func getFriends() async throws -> [FriendInfo] {
        try await lastFm.getFriends()
    }

    func checkForUpdates() async throws -> UpdateInfo? {
        try await UpdateChecker().check()
    }

    func getNowPlayingString() -> String? {
        guard let t = currentTrack else { return nil }
        return "♪ \(t.artist) – \(t.title)"
    }

    private func addLog(_ kind: LogEntry.Kind, _ text: String) {
        if kind == .scrobbled, let idx = logs.firstIndex(where: { $0.kind == .nowPlaying && $0.text == text }) {
            logs[idx] = LogEntry(kind: .scrobbled, text: text, timestamp: Date())
            return
        }
        let entry = LogEntry(kind: kind, text: text, timestamp: Date())
        logs.insert(entry, at: 0)
        if logs.count > 50 { logs = Array(logs.prefix(50)) }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
