import Foundation
import AppKit

private struct MusicPayload: Sendable {
    let state: String
    let name: String
    let artist: String
    let album: String
    let albumArtist: String
    let totalTimeMs: Double
    let trackNumber: Int
}

@MainActor
final class MediaWatcher {
    var onTrackChanged: ((Track?) -> Void)?
    /// "Paused" — the engine keeps the track and freezes its listen-time clock.
    var onPlaybackPaused: (() -> Void)?
    /// "Stopped" (debounced) — the track is gone.
    var onPlaybackStopped: (() -> Void)?
    private var debounceTask: Task<Void, Never>?
    private var observation: NSObjectProtocol?
    private var filterAppleMusicOnly: Bool

    init(filterAppleMusicOnly: Bool = true) {
        self.filterAppleMusicOnly = filterAppleMusicOnly
    }

    func start() {
        observation = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let info = notification.userInfo ?? [:]
            let payload = MusicPayload(
                state: info["Player State"] as? String ?? "",
                name: info["Name"] as? String ?? "",
                artist: info["Artist"] as? String ?? "",
                album: info["Album"] as? String ?? "",
                albumArtist: info["Album Artist"] as? String ?? "",
                totalTimeMs: info["Total Time"] as? Double ?? 0,
                trackNumber: info["Track Number"] as? Int ?? 0
            )
            Task { @MainActor in self.handlePayload(payload) }
        }
    }

    func stop() {
        if let obs = observation {
            DistributedNotificationCenter.default().removeObserver(obs)
            observation = nil
        }
    }

    private func handlePayload(_ p: MusicPayload) {
        if p.state == "Paused" {
            debounceTask?.cancel()
            onPlaybackPaused?()
            return
        }
        if p.state == "Stopped" {
            // Apple Music briefly emits Stopped between tracks — debounce so a
            // real track that follows can cancel the empty event.
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                self.onPlaybackStopped?()
            }
            return
        }

        guard p.state == "Playing" else { return }

        let title = p.name.trimmingCharacters(in: .whitespaces)
        let artist = p.artist.trimmingCharacters(in: .whitespaces)
        let album = p.album.trimmingCharacters(in: .whitespaces)
        let albumArtist = p.albumArtist.trimmingCharacters(in: .whitespaces)

        guard !title.isEmpty, !artist.isEmpty else { return }

        let track = Track(
            title: title,
            artist: artist,
            album: album,
            albumArtist: albumArtist.isEmpty ? artist : albumArtist,
            durationSeconds: Int(p.totalTimeMs / 1000),
            trackNumber: p.trackNumber,
            detectedAt: Date(),
            sourceApp: "Apple Music"
        )

        debounceTask?.cancel()
        onTrackChanged?(track)
    }
}
