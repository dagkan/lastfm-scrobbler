import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var settings: AppSettings
    @Published var isAuthenticated: Bool = false
    @Published var avatarUrl: String = ""

    let engine: ScrobbleEngine
    let db: Database

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("LastFmScrobbler")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbPath = dir.appendingPathComponent("lastfm.db").path

        self.db = Database(path: dbPath)
        var loaded = db.loadSettings()
        let hadInstallId = loaded.installId.count == 32
        Telemetry.configure(settings: &loaded)
        if !hadInstallId { db.saveSettings(loaded) }
        self.settings = loaded
        self.engine = ScrobbleEngine(db: db, settings: loaded)
        self.isAuthenticated = !loaded.sessionKey.isEmpty

        Loc.setLanguage(loaded.language)
    }

    func start() async {
        engine.onEditBeforeScrobble = { track in
            await MainActor.run { return track }
        }
        await engine.start()
        if isAuthenticated { await fetchAvatar() }
    }

    func fetchAvatar() async {
        guard let info = try? await engine.getUserInfo() else { return }
        avatarUrl = info.avatarUrl
    }

    func saveSettings() {
        db.saveSettings(settings)
        engine.applySettings(settings)
        Telemetry.apply(settings: settings)
        Loc.setLanguage(settings.language)
    }

    func logOut() {
        settings.sessionKey = ""
        settings.username = ""
        isAuthenticated = false
        avatarUrl = ""
        db.saveSettings(settings)
        engine.applySettings(settings)
    }
}
