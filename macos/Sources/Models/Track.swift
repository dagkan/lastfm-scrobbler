import Foundation

struct Track: Sendable, Equatable {
    var title: String
    var artist: String
    var album: String
    var albumArtist: String
    var durationSeconds: Int
    var trackNumber: Int
    var detectedAt: Date
    var sourceApp: String

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !artist.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func isSameTrack(_ other: Track) -> Bool {
        title.lowercased() == other.title.lowercased() &&
        artist.lowercased() == other.artist.lowercased()
    }

    func clone() -> Track { self }
}

struct ScrobbleRecord: Identifiable, Sendable {
    let id: Int64
    var title: String
    var artist: String
    var album: String
    var scrobbledAt: Date
    var success: Bool
    var errorMessage: String?
}

struct PendingScrobble: Sendable {
    let id: Int64
    let title: String
    let artist: String
    let album: String
    let playedAt: Date
    let queuedAt: Date
}
