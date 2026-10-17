import Foundation
import CryptoKit

struct VersionEntry: Identifiable, Sendable {
    let id: String
    let version: String
    let date: String
    let notes: [String]
}

struct UpdateChecker: Sendable {
    // Served by the same worker route that proxies the Windows manifests
    // (`GET /lastfm-scrobbler/*` → R2), so no worker change is needed.
    private let manifestUrl = Links.proxyBase + "/lastfm-scrobbler/macos/latest.json"
    private let versionsUrl = Links.proxyBase + "/lastfm-scrobbler/macos/versions.json"
    private let session = URLSession.shared

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    func check() async throws -> UpdateInfo? {
        guard let url = URL(string: manifestUrl) else { return nil }
        let (data, _) = try await session.data(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String,
              let downloadUrl = json["url"] as? String,
              let sha256 = json["sha256"] as? String else { return nil }
        guard isNewer(version, than: currentVersion) else { return nil }

        var notes = Self.parseNotes(json["notes"])
        if notes.isEmpty, let history = try? await getVersionHistory(),
           let entry = history.first(where: { $0.version == version }) {
            notes = entry.notes
        }
        return UpdateInfo(version: version, downloadUrl: downloadUrl, sha256: sha256, releaseNotes: notes)
    }

    func getVersionHistory() async throws -> [VersionEntry] {
        guard let url = URL(string: versionsUrl) else { return [] }
        let (data, _) = try await session.data(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return json.compactMap { entry -> VersionEntry? in
            guard let v = entry["version"] as? String else { return nil }
            return VersionEntry(id: v, version: v,
                                date: entry["date"] as? String ?? "",
                                notes: Self.parseNotes(entry["notes"]))
        }
    }

    /// `notes` is an array in most entries but a bare string in a few — accept both.
    static func parseNotes(_ raw: Any?) -> [String] {
        if let arr = raw as? [String] { return arr.filter { !$0.isEmpty } }
        if let s = raw as? String, !s.isEmpty { return [s] }
        return []
    }

    /// Downloads the DMG to a temp location and verifies its SHA-256 before
    /// handing it back. Throws on mismatch so a tampered/corrupt file never opens.
    func download(info: UpdateInfo) async throws -> URL {
        guard let url = URL(string: info.downloadUrl) else { throw URLError(.badURL) }
        let (localUrl, _) = try await session.download(from: url)

        let data = try Data(contentsOf: localUrl)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == info.sha256.lowercased() else {
            try? FileManager.default.removeItem(at: localUrl)
            throw UpdateError.checksumMismatch(expected: info.sha256, actual: digest)
        }

        let dest = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LastFmScrobbler-\(info.version).dmg")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: localUrl, to: dest)
        return dest
    }

    private func isNewer(_ version: String, than current: String) -> Bool {
        let a = version.split(separator: ".").compactMap { Int($0) }
        let b = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(a.count, b.count) {
            let av = i < a.count ? a[i] : 0
            let bv = i < b.count ? b[i] : 0
            if av != bv { return av > bv }
        }
        return false
    }
}

enum UpdateError: LocalizedError {
    case checksumMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .checksumMismatch(let e, let a):
            return "SHA-256 mismatch — expected \(e.prefix(12))…, got \(a.prefix(12))…"
        }
    }
}
