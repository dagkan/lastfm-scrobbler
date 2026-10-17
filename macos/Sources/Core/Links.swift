import Foundation

/// Every outbound project URL in one place (mirrors Core/Links.cs on Windows).
enum Links {
    static let repo     = "https://github.com/dagkan/lastfm-scrobbler"
    static let issues   = repo + "/issues/new"
    static let releases = repo + "/releases"
    static let sponsor  = "https://github.com/sponsors/dagkan"
    static let coffee   = "https://buymeacoffee.com/daiquiri"

    /// Cloudflare Worker that proxies Last.fm, serves update manifests from R2
    /// and receives telemetry. Baked into every shipped build — see ROADMAP.md
    /// before ever changing it.
    static let proxyBase = "https://proxy.lastfm.spacechild.dev"
}
