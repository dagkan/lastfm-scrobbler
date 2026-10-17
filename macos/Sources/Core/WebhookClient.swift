import Foundation

struct WebhookClient: Sendable {
    private let session = URLSession.shared

    func post(url: String, event: String, track: Track?, success: Bool) {
        guard !url.isEmpty, let webhookUrl = URL(string: url) else { return }
        Task {
            var payload: [String: Any] = [
                "@event": event,
                "success": success,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
            if let t = track {
                payload["track"] = [
                    "title": t.title,
                    "artist": t.artist,
                    "album": t.album,
                    "duration_seconds": t.durationSeconds,
                    "source": t.sourceApp
                ]
            }
            guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
            var req = URLRequest(url: webhookUrl, timeoutInterval: 10)
            req.httpMethod = "POST"
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            _ = try? await session.data(for: req)
        }
    }
}
