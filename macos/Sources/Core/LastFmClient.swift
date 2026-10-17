import Foundation

struct LastFmError: Error {
    let code: Int
    let message: String
}

struct UserInfo: Sendable {
    let username: String
    let avatarUrl: String
    let playcount: Int
}

struct ArtistInfo: Sendable {
    let bio: String
    let similarArtists: [String]
}

struct FriendInfo: Identifiable, Sendable {
    let id: String
    let username: String
    let avatarUrl: String
    let nowPlayingTrack: String?
    let isNowPlaying: Bool
    let playcount: Int
    let country: String
    let memberSince: Int  // unix timestamp
}

struct TopItem: Identifiable, Sendable {
    let id: String
    let name: String
    let secondary: String
    let playcount: Int
}

struct UpdateInfo: Sendable {
    let version: String
    let downloadUrl: String
    let sha256: String
    let releaseNotes: [String]
}

// All requests go through the Cloudflare Worker proxy.
// The Worker injects api_key and generates api_sig server-side.
// Client only sends _sign: "1" to request signing — never handles keys locally.
actor LastFmClient {
    private let baseUrl = Links.proxyBase + "/"
    private let session = URLSession.shared
    private var sessionKey: String = ""

    func setSessionKey(_ key: String) { sessionKey = key }

    // MARK: - Auth

    func getAuthUrl() async throws -> (token: String, url: String) {
        let json = try await call("auth.getToken", args: [:], signed: false)
        let token = json["token"] as? String ?? ""
        let url = json["_authUrl"] as? String ?? ""
        guard !token.isEmpty, !url.isEmpty else {
            throw LastFmError(code: -1, message: "No token/authUrl from proxy")
        }
        return (token, url)
    }

    func getSession(token: String) async throws -> (sessionKey: String, username: String) {
        let json = try await call("auth.getSession", args: ["token": token], signed: true)
        guard let sess = json["session"] as? [String: Any],
              let key = sess["key"] as? String,
              let name = sess["name"] as? String else {
            throw LastFmError(code: -1, message: "Invalid session response")
        }
        return (key, name)
    }

    // MARK: - Scrobble

    func scrobble(track: Track, timestamp: Date) async throws {
        var args: [String: String] = [
            "artist":      track.artist,
            "track":       track.title,
            "timestamp":   "\(Int(timestamp.timeIntervalSince1970))",
            "sk":          sessionKey,
        ]
        if !track.album.isEmpty      { args["album"]       = track.album }
        if !track.albumArtist.isEmpty { args["albumArtist"] = track.albumArtist }
        if track.durationSeconds > 0  { args["duration"]    = "\(track.durationSeconds)" }
        _ = try await call("track.scrobble", args: args, signed: true)
    }

    func scrobbleBatch(_ items: [(track: Track, playedAt: Date)]) async throws {
        var args: [String: String] = ["sk": sessionKey]
        for (i, item) in items.prefix(50).enumerated() {
            args["artist[\(i)]"]    = item.track.artist
            args["track[\(i)]"]     = item.track.title
            args["timestamp[\(i)]"] = "\(Int(item.playedAt.timeIntervalSince1970))"
            if !item.track.album.isEmpty { args["album[\(i)]"] = item.track.album }
        }
        _ = try await call("track.scrobble", args: args, signed: true)
    }

    func updateNowPlaying(track: Track) async throws {
        var args: [String: String] = [
            "artist": track.artist,
            "track":  track.title,
            "sk":     sessionKey,
        ]
        if !track.album.isEmpty     { args["album"]    = track.album }
        if track.durationSeconds > 0 { args["duration"] = "\(track.durationSeconds)" }
        _ = try await call("track.updateNowPlaying", args: args, signed: true)
    }

    func loveTrack(artist: String, title: String) async throws {
        _ = try await call("track.love", args: ["artist": artist, "track": title, "sk": sessionKey], signed: true)
    }

    func unloveTrack(artist: String, title: String) async throws {
        _ = try await call("track.unlove", args: ["artist": artist, "track": title, "sk": sessionKey], signed: true)
    }

    func getAlbumName(artist: String, title: String) async throws -> String? {
        let json = try await call("track.getInfo", args: ["artist": artist, "track": title, "autocorrect": "1"], signed: false)
        guard let t = json["track"] as? [String: Any],
              let album = t["album"] as? [String: Any],
              let title = album["title"] as? String else { return nil }
        return title
    }

    // MARK: - User Info

    func getUserInfo() async throws -> UserInfo {
        let json = try await call("user.getInfo", args: ["sk": sessionKey], signed: true)
        guard let user = json["user"] as? [String: Any] else {
            throw LastFmError(code: -1, message: "No user data")
        }
        let name = user["name"] as? String ?? ""
        let playcount = Int(user["playcount"] as? String ?? "0") ?? 0
        let images = user["image"] as? [[String: Any]] ?? []
        let avatar = images.last?["#text"] as? String ?? ""
        return UserInfo(username: name, avatarUrl: avatar, playcount: playcount)
    }

    func getArtistInfo(artist: String) async throws -> ArtistInfo {
        let json = try await call("artist.getInfo", args: ["artist": artist, "autocorrect": "1"], signed: false)
        guard let a = json["artist"] as? [String: Any] else {
            return ArtistInfo(bio: "", similarArtists: [])
        }
        var bio = ""
        if let bioObj = a["bio"] as? [String: Any],
           let summary = bioObj["summary"] as? String {
            bio = summary
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if bio.count > 280 { bio = String(bio.prefix(280)) + "…" }
        }
        var similar: [String] = []
        if let similarObj = a["similar"] as? [String: Any],
           let artists = similarObj["artist"] as? [[String: Any]] {
            similar = artists.prefix(4).compactMap { $0["name"] as? String }
        }
        return ArtistInfo(bio: bio, similarArtists: similar)
    }

    func getArtistTopTags(artist: String) async throws -> [String] {
        let json = try await call("artist.getTopTags", args: ["artist": artist, "autocorrect": "1"], signed: false)
        guard let tagsObj = json["toptags"] as? [String: Any],
              let tags = tagsObj["tag"] as? [[String: Any]] else { return [] }
        return tags.prefix(5).compactMap { $0["name"] as? String }
    }

    func getUserTopArtists(period: String = "overall") async throws -> [TopItem] {
        let json = try await call("user.getTopArtists", args: ["period": period, "limit": "10", "sk": sessionKey], signed: true)
        guard let top = json["topartists"] as? [String: Any],
              let artists = top["artist"] as? [[String: Any]] else { return [] }
        return artists.compactMap { a -> TopItem? in
            guard let name = a["name"] as? String else { return nil }
            let playcount = Int(a["playcount"] as? String ?? "0") ?? 0
            return TopItem(id: name, name: name, secondary: "", playcount: playcount)
        }
    }

    func getUserTopTracks(period: String = "overall") async throws -> [TopItem] {
        let json = try await call("user.getTopTracks", args: ["period": period, "limit": "10", "sk": sessionKey], signed: true)
        guard let top = json["toptracks"] as? [String: Any],
              let tracks = top["track"] as? [[String: Any]] else { return [] }
        return tracks.compactMap { t -> TopItem? in
            guard let name = t["name"] as? String,
                  let artist = (t["artist"] as? [String: Any])?["name"] as? String else { return nil }
            let playcount = Int(t["playcount"] as? String ?? "0") ?? 0
            return TopItem(id: "\(artist)-\(name)", name: name, secondary: artist, playcount: playcount)
        }
    }

    func getFriends() async throws -> [FriendInfo] {
        let json = try await call("user.getFriends", args: ["recenttracks": "1", "limit": "50", "sk": sessionKey], signed: true)
        guard let friends = json["friends"] as? [String: Any],
              let users = friends["user"] as? [[String: Any]] else { return [] }
        return users.compactMap { u -> FriendInfo? in
            guard let name = u["name"] as? String else { return nil }
            let images = u["image"] as? [[String: Any]] ?? []
            let avatar = images.last?["#text"] as? String ?? ""
            var nowPlaying: String? = nil
            var isNP = false
            if let rt = u["recenttrack"] as? [String: Any] {
                if let attr = rt["@attr"] as? [String: Any], attr["nowplaying"] as? String == "true" { isNP = true }
                let trackName = rt["name"] as? String ?? ""
                let artistName = (rt["artist"] as? [String: Any])?["#text"] as? String ?? ""
                if !trackName.isEmpty || !artistName.isEmpty {
                    nowPlaying = "\(artistName) – \(trackName)"
                }
            }
            let playcount = Int(u["playcount"] as? String ?? "0") ?? 0
            let country = u["country"] as? String ?? ""
            let memberSince = Int((u["registered"] as? [String: Any])?["unixtime"] as? String ?? "0") ?? 0
            return FriendInfo(id: name, username: name, avatarUrl: avatar,
                              nowPlayingTrack: nowPlaying, isNowPlaying: isNP,
                              playcount: playcount, country: country, memberSince: memberSince)
        }
    }

    // MARK: - HTTP

    private func call(_ method: String, args: [String: String], signed: Bool) async throws -> [String: Any] {
        var params = args
        params["method"] = method
        if signed { params["_sign"] = "1" }

        var request = URLRequest(url: URL(string: baseUrl)!)
        request.httpMethod = "POST"
        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await session.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LastFmError(code: -1, message: "Invalid JSON response")
        }
        if let err = json["error"] as? Int, let msg = json["message"] as? String {
            throw LastFmError(code: err, message: msg)
        }
        return json
    }
}
