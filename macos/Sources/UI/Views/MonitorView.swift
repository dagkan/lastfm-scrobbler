import SwiftUI

struct MonitorView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var engine: ScrobbleEngine
    @State private var artistInfo: ArtistInfo?
    @State private var tags: [String] = []
    @State private var loadingArtist = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                nowPlayingCard
                statsStrip
                if !engine.logs.isEmpty { logSection }
            }
            .padding(20)
        }
        .background(Color(nsColor: NSColor(red: 0.094, green: 0.094, blue: 0.094, alpha: 1)))
        .onChange(of: engine.currentTrack?.artist) { artist in
            if let artist { fetchArtistInfo(artist: artist) }
            else { artistInfo = nil; tags = [] }
        }
    }

    // MARK: - Now Playing Card

    private var nowPlayingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let track = engine.currentTrack {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(Loc.t("NowPlaying"), systemImage: "waveform")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accentColor)

                        Text(track.title)
                            .font(.title2.bold())
                            .lineLimit(2)
                        Text(track.artist)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        if !track.album.isEmpty {
                            Text(track.album)
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    loveButton
                }

                if track.durationSeconds > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: engine.scrobbleProgress)
                            .progressViewStyle(.linear)
                            .tint(accentColor)
                        HStack {
                            Text(formatTime(engine.playedSeconds))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(engine.scrobbleProgress >= 1 ? Loc.t("ScrobbledOk")
                                 : engine.isPlaying ? Loc.t("WaitingToScrobble") : Loc.t("Paused"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(formatTime(track.durationSeconds))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let info = artistInfo {
                    Divider().opacity(0.4)
                    artistBioHeader(info)
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "pause.circle")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(Loc.t("NotPlaying"))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }

    private func artistBioHeader(_ info: ArtistInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !info.bio.isEmpty {
                Text(info.bio)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            if !tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(accentColor.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
            }
            if !info.similarArtists.isEmpty {
                HStack(spacing: 4) {
                    Text("Similar:")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(info.similarArtists.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var loveButton: some View {
        Button {
            Task { await engine.loveTrack() }
        } label: {
            Image(systemName: "heart.fill")
                .font(.title2)
                .foregroundStyle(accentColor)
        }
        .buttonStyle(.plain)
        .disabled(engine.currentTrack == nil)
    }

    // MARK: - Stats Strip

    private var statsStrip: some View {
        let stats = appState.db.getStats()
        let streak = appState.db.getCurrentStreak()
        return HStack(spacing: 12) {
            statCard(label: Loc.t("StatToday"), value: "\(stats.today)")
            statCard(label: Loc.t("StatWeek"), value: "\(stats.thisWeek)")
            statCard(label: Loc.t("StatTotal"), value: "\(stats.total)")
            statCard(label: Loc.t("StatStreak"), value: "\(streak)d")
            if engine.pendingCount > 0 {
                statCard(label: Loc.t("StatQueue"), value: "\(engine.pendingCount)")
                    .foregroundStyle(.orange)
            }
        }
    }

    private func statCard(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
    }

    // MARK: - Log

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Activity")
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(engine.logs.prefix(10)) { entry in
                LogRow(entry: entry)
            }
        }
    }

    private func fetchArtistInfo(artist: String) {
        guard !loadingArtist else { return }
        loadingArtist = true
        Task {
            async let info = try? appState.engine.getArtistInfo(artist: artist)
            async let t = try? appState.engine.getArtistTopTags(artist: artist)
            artistInfo = await info
            tags = await t ?? []
            loadingArtist = false
        }
    }

    private var accentColor: Color {
        Color(hex: appState.settings.accentColor) ?? .red
    }

    private func formatTime(_ seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
            Text(entry.text)
                .font(.caption)
                .lineLimit(1)
            Spacer()
            Text(timeString)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
            Text(statusLabel)
                .font(.caption2)
                .foregroundStyle(dotColor)
        }
    }

    private var dotColor: Color {
        switch entry.kind {
        case .nowPlaying:   return .blue
        case .scrobbled:    return .green
        case .loved:        return .pink
        case .unloved:      return .gray
        case .failed:       return .red
        case .manual:       return .purple
        case .queueFlushed: return .gray
        }
    }

    private var statusLabel: String {
        switch entry.kind {
        case .nowPlaying:   return Loc.t("NowPlaying")
        case .scrobbled:    return Loc.t("ScrobbledOk")
        case .loved:        return Loc.t("Loved")
        case .unloved:      return Loc.t("Unloved")
        case .failed:       return Loc.t("ScrobbleFailed")
        case .manual:       return "Manual"
        case .queueFlushed: return "Flushed"
        }
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: entry.timestamp)
    }
}
