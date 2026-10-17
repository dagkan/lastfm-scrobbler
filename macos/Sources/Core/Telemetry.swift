import Foundation

/// Anonymous, opt-out usage pings and crash reports — same contract as the
/// Windows client (`/telemetry/ping|scrobble|crash` on the proxy worker).
/// Only a random install id, the app version and exception details are sent;
/// never tracks, artists or the Last.fm username.
enum Telemetry {
    nonisolated(unsafe) private static var enabled = false
    nonisolated(unsafe) private static var installId = ""
    nonisolated(unsafe) private static var recentCrashes: [String: Date] = [:]
    private static let lock = NSLock()
    private static let dedupeWindow: TimeInterval = 600

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Call once at startup. Generates and persists the install id if missing.
    static func configure(settings: inout AppSettings) {
        if settings.installId.count != 32 {
            settings.installId = (0..<16).map { _ in String(format: "%02x", Int.random(in: 0...255)) }.joined()
        }
        lock.lock(); defer { lock.unlock() }
        enabled   = settings.telemetryEnabled
        installId = settings.installId
    }

    static func apply(settings: AppSettings) {
        lock.lock(); defer { lock.unlock() }
        enabled   = settings.telemetryEnabled
        installId = settings.installId
    }

    static func ping()               { post("ping",     [:]) }
    static func scrobble(_ n: Int)   { post("scrobble", ["count": n]) }

    static func crash(type: String, message: String, stack: String) {
        let key = type + "|" + message
        lock.lock()
        let now = Date()
        if let last = recentCrashes[key], now.timeIntervalSince(last) < dedupeWindow { lock.unlock(); return }
        recentCrashes[key] = now
        lock.unlock()
        post("crash", [
            "exceptionType": type,
            "message":       scrub(message),
            "stackTrace":    scrub(stack),
        ])
    }

    /// Reports uncaught Objective-C exceptions (Swift runtime traps can't be
    /// intercepted in-process; those surface via the system crash reporter).
    static func installCrashHandlers() {
        NSSetUncaughtExceptionHandler { exception in
            let stack = exception.callStackSymbols.joined(separator: "\n")
            Telemetry.crash(type: exception.name.rawValue,
                            message: exception.reason ?? "",
                            stack: stack)
            // The process is about to die — give the request a moment to leave.
            Thread.sleep(forTimeInterval: 1.5)
        }
    }

    // MARK: - Internals

    /// Exception text can embed the home directory (and the account name with it).
    private static func scrub(_ s: String) -> String {
        var out = s
        let home = NSHomeDirectory()
        if !home.isEmpty { out = out.replacingOccurrences(of: home, with: "~") }
        let user = NSUserName()
        if user.count > 2 { out = out.replacingOccurrences(of: user, with: "<user>", options: .caseInsensitive) }
        return out
    }

    private static func post(_ endpoint: String, _ fields: [String: Any]) {
        lock.lock()
        let isEnabled = enabled, id = installId
        lock.unlock()
        guard isEnabled, id.count == 32,
              let url = URL(string: Links.proxyBase + "/telemetry/" + endpoint) else { return }

        var body = fields
        body["installId"]  = id
        body["appVersion"] = appVersion
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req).resume() // fire-and-forget, best effort
    }
}
