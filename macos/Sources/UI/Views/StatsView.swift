import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var engine: ScrobbleEngine
    @State private var period = "overall"
    @State private var topArtists: [TopItem] = []
    @State private var topTracks: [TopItem] = []
    @State private var dailyData: [(String, Int)] = []
    @State private var loading = false

    let periods = ["7day", "1month", "3month", "6month", "12month", "overall"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                statsHeader
                chartSection
                HStack(alignment: .top, spacing: 16) {
                    topListSection(title: Loc.t("StatsTopArtists"), items: topArtists)
                    topListSection(title: Loc.t("StatsTopTracks"), items: topTracks.map {
                        TopItem(id: $0.id, name: $0.name, secondary: $0.secondary, playcount: $0.playcount)
                    })
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: NSColor(red: 0.094, green: 0.094, blue: 0.094, alpha: 1)))
        .onAppear { load() }
        .onChange(of: period) { _ in loadRemote() }
    }

    private var statsHeader: some View {
        HStack(spacing: 12) {
            let stats = appState.db.getStats()
            statCard(Loc.t("StatTotal"), "\(stats.total)")
            statCard(Loc.t("StatWeek"), "\(stats.thisWeek)")
            statCard(Loc.t("StatToday"), "\(stats.today)")
            statCard(Loc.t("StatStreak"), "\(appState.db.getCurrentStreak())d")
            Spacer()
            Picker("Period", selection: $period) {
                ForEach(periods, id: \.self) { p in Text(p).tag(p) }
            }
            .frame(width: 160)
        }
    }

    private func statCard(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Loc.t("StatsLast14Days"))
                .font(.headline)
                .foregroundStyle(.secondary)

            if dailyData.isEmpty {
                Rectangle()
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 120)
                    .cornerRadius(10)
            } else {
                Chart {
                    ForEach(dailyData, id: \.0) { day, count in
                        BarMark(
                            x: .value("Date", day),
                            y: .value("Scrobbles", count)
                        )
                        .foregroundStyle(accentColor)
                        .cornerRadius(3)
                    }
                }
                .frame(height: 120)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 7)) }
            }
        }
    }

    private func topListSection(title: String, items: [TopItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                HStack(spacing: 10) {
                    Text("\(i + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(width: 20, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.callout).lineLimit(1)
                        if !item.secondary.isEmpty {
                            Text(item.secondary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    Text("\(item.playcount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if i < items.count - 1 { Divider() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }

    private func load() {
        dailyData = appState.db.getDailyScrobbles(days: 14).map { ($0.date, $0.count) }
        loadRemote()
    }

    private func loadRemote() {
        guard !loading else { return }
        loading = true
        Task {
            async let artists = try? engine.getUserTopArtists(period: period)
            async let tracks = try? engine.getUserTopTracks(period: period)
            topArtists = await artists ?? []
            topTracks = await tracks ?? []
            loading = false
        }
    }

    private var accentColor: Color {
        Color(hex: appState.settings.accentColor) ?? .red
    }
}
