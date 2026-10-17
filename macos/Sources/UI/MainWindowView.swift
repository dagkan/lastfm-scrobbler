import SwiftUI

enum NavPage: String, CaseIterable {
    case monitor = "Monitor"
    case history = "History"
    case stats = "Stats"
    case friends = "Friends"
    case scrobbling = "Scrobbling"
    case normalization = "Normalization"
    case about = "About"

    var icon: String {
        switch self {
        case .monitor:       return "waveform"
        case .history:       return "clock"
        case .stats:         return "chart.bar"
        case .friends:       return "person.2"
        case .scrobbling:    return "gear"
        case .normalization: return "wand.and.stars"
        case .about:         return "info.circle"
        }
    }

    var locKey: String {
        switch self {
        case .monitor:       return "NavMonitor"
        case .history:       return "NavHistory"
        case .stats:         return "NavStats"
        case .friends:       return "NavFriends"
        case .scrobbling:    return "NavScrobbling"
        case .normalization: return "NavNormalization"
        case .about:         return "NavAbout"
        }
    }
}

struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var engine: ScrobbleEngine
    @State private var selectedPage: NavPage = .monitor
    @State private var showAuth = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            content
        }
        .sheet(isPresented: $showAuth) {
            AuthView(isPresented: $showAuth)
                .environmentObject(appState)
        }
        .onAppear {
            if !appState.isAuthenticated { showAuth = true }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App title
            HStack(spacing: 8) {
                Image(systemName: "music.note.list")
                    .foregroundStyle(accentColor)
                Text("Last.fm Scrobbler")
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
                .padding(.bottom, 8)

            ForEach(NavPage.allCases, id: \.self) { page in
                SidebarRow(page: page, isSelected: selectedPage == page)
                    .onTapGesture { selectedPage = page }
            }

            Spacer()

            if engine.pendingCount > 0 {
                HStack(spacing: 6) {
                    Circle().fill(.orange).frame(width: 6, height: 6)
                    Text("\(engine.pendingCount) queued")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            Divider()
            profileFooter
        }
        .frame(width: 200)
        .background(Color(nsColor: NSColor(red: 0.059, green: 0.059, blue: 0.059, alpha: 1)))
    }

    private var profileFooter: some View {
        Group {
            if appState.isAuthenticated {
                HStack(spacing: 10) {
                    AsyncImage(url: URL(string: appState.avatarUrl)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.settings.username)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text(Loc.t("Connected"))
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }

                    Spacer()

                    Menu {
                        Button {
                            if let url = URL(string: "https://www.last.fm/user/\(appState.settings.username)") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Label(Loc.t("BtnVisitProfile"), systemImage: "arrow.up.right.square")
                        }
                        Divider()
                        Button(role: .destructive) {
                            appState.logOut()
                        } label: {
                            Label(Loc.t("LogOut"), systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            } else {
                Button(Loc.t("LogIn")) { showAuth = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedPage {
        case .monitor:       MonitorView()
        case .history:       HistoryView()
        case .stats:         StatsView()
        case .friends:       FriendsView()
        case .scrobbling:    SettingsView()
        case .normalization: NormalizationView()
        case .about:         AboutView()
        }
    }

    private var accentColor: Color {
        Color(hex: appState.settings.accentColor) ?? .red
    }
}

struct SidebarRow: View {
    let page: NavPage
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: page.icon)
                .frame(width: 16)
                .foregroundStyle(isSelected ? .primary : .secondary)
            Text(Loc.t(page.locKey))
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? .primary : .secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isSelected ? Color.white.opacity(0.08) : Color.clear)
        .cornerRadius(6)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }
}

extension Color {
    init?(hex: String) {
        var str = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if str.hasPrefix("#") { str.removeFirst() }
        guard str.count == 6, let val = UInt64(str, radix: 16) else { return nil }
        self.init(
            red: Double((val >> 16) & 0xFF) / 255,
            green: Double((val >> 8) & 0xFF) / 255,
            blue: Double(val & 0xFF) / 255
        )
    }
}
