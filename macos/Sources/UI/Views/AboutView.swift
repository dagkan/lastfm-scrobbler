import SwiftUI

struct AboutView: View {
    @EnvironmentObject var appState: AppState
    @State private var versionHistory: [VersionEntry] = []
    @State private var showVersionHistory = false
    @State private var updateInfo: UpdateInfo?
    @State private var checking = false
    @State private var downloadState: DownloadState = .idle

    enum DownloadState: Equatable { case idle, downloading, failed(String) }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroCard

                Text(Loc.t("AboutDescription"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().opacity(0.4)

                // GitHub-styled buttons: GitHub mark, Sponsors heart.
                HStack(spacing: 10) {
                    GhButton(title: "GitHub", icon: .github) { open(Links.repo) }
                    GhButton(title: "Sponsor", icon: .heart) { open(Links.sponsor) }
                    GhButton(title: Loc.t("BtnBuyCoffee"), icon: .none) { open(Links.coffee) }
                    Spacer()
                }

                Divider().opacity(0.4)

                VStack(alignment: .leading, spacing: 8) {
                    Text(Loc.t("InstalledVersion").uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 12) {
                        Text("v\(version)").font(.callout)
                        GhButton(title: Loc.t("LblVersionHistory"), icon: .none) {
                            loadHistory()
                            showVersionHistory = true
                        }
                        Button(Loc.t("BtnCheckForUpdates")) { checkForUpdates() }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .disabled(checking)
                    }
                }

                if let info = updateInfo {
                    updateBanner(info)
                }

                Divider().opacity(0.4)

                HStack(spacing: 6) {
                    Text("© \(Calendar.current.component(.year, from: Date())) Dagkan Bayramoglu  ·  MIT License")
                    Text("·")
                    Button(Loc.t("ReportBug")) { open(Links.issues) }.buttonStyle(.plain)
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            .padding(24)
        }
        .background(Color(nsColor: NSColor(red: 0.094, green: 0.094, blue: 0.094, alpha: 1)))
        .onAppear { checkForUpdates() }
        .sheet(isPresented: $showVersionHistory) {
            VersionHistoryView(entries: versionHistory, currentVersion: version, isPresented: $showVersionHistory)
        }
    }

    private var heroCard: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("Last.fm Scrobbler").font(.title2.bold())
                HStack(spacing: 8) {
                    Text("v\(version)").font(.caption).foregroundStyle(.secondary)
                    Text("Open source  ·  MIT License").font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06)))
        .cornerRadius(12)
    }

    private func updateBanner(_ info: UpdateInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Loc.t("UpdateAvailable")).font(.callout.weight(.semibold))
                    Text("Version \(info.version)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                switch downloadState {
                case .downloading:
                    ProgressView().controlSize(.small)
                default:
                    Button(Loc.t("Download")) { download(info) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            if !info.releaseNotes.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(info.releaseNotes, id: \.self) { note in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                            Text(note)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            if case .failed(let msg) = downloadState {
                Text(msg).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(Color.green.opacity(0.08))
        .cornerRadius(10)
    }

    private func checkForUpdates() {
        checking = true
        Task {
            updateInfo = try? await UpdateChecker().check()
            checking = false
        }
    }

    private func download(_ info: UpdateInfo) {
        downloadState = .downloading
        Task {
            do {
                let dmg = try await UpdateChecker().download(info: info)
                downloadState = .idle
                NSWorkspace.shared.open(dmg) // mounts the DMG; user drags the app over
            } catch {
                downloadState = .failed(error.localizedDescription)
            }
        }
    }

    private func loadHistory() {
        Task {
            versionHistory = (try? await UpdateChecker().getVersionHistory()) ?? []
        }
    }

    private func open(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
}

/// A button styled after GitHub's default dark-theme button (6 pt radius,
/// #21262d fill, hairline border, optional leading icon).
struct GhButton: View {
    enum Icon { case none, github, heart }

    let title: String
    let icon: Icon
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                switch icon {
                case .github:
                    GitHubMark().fill(Color(red: 0.79, green: 0.82, blue: 0.85)).frame(width: 15, height: 15)
                case .heart:
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 0.86, green: 0.38, blue: 0.64))
                case .none:
                    EmptyView()
                }
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color(red: 0.79, green: 0.82, blue: 0.85))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(hover ? Color(red: 0.19, green: 0.21, blue: 0.24) : Color(red: 0.13, green: 0.15, blue: 0.18))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1)))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Octicon `mark-github` (MIT, primer/octicons) on a 16×16 grid.
struct GitHubMark: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 16
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        p.move(to: pt(8, 0))
        p.addCurve(to: pt(16, 8),     control1: pt(12.42, 0),    control2: pt(16, 3.58))
        p.addCurve(to: pt(10.55, 15.59), control1: pt(16, 11.54), control2: pt(13.71, 14.53))
        p.addCurve(to: pt(10, 15.21),  control1: pt(10.15, 15.67), control2: pt(10, 15.42))
        p.addCurve(to: pt(10.01, 13.01), control1: pt(10, 14.94), control2: pt(10.01, 14.08))
        p.addCurve(to: pt(9.47, 11.53), control1: pt(10.01, 12.26), control2: pt(9.76, 11.78))
        p.addCurve(to: pt(13.12, 7.58), control1: pt(11.25, 11.33), control2: pt(13.12, 10.65))
        p.addCurve(to: pt(12.3, 5.43),  control1: pt(13.12, 6.7),   control2: pt(12.81, 5.99))
        p.addCurve(to: pt(12.22, 3.31), control1: pt(12.38, 5.23),  control2: pt(12.66, 4.41))
        p.addCurve(to: pt(10.02, 4.13), control1: pt(12.22, 3.31),  control2: pt(11.55, 3.09))
        p.addCurve(to: pt(8.02, 3.86),  control1: pt(9.38, 3.95),   control2: pt(8.7, 3.86))
        p.addCurve(to: pt(6.02, 4.13),  control1: pt(7.34, 3.86),   control2: pt(6.66, 3.95))
        p.addCurve(to: pt(3.82, 3.31),  control1: pt(4.49, 3.1),    control2: pt(3.82, 3.31))
        p.addCurve(to: pt(3.74, 5.43),  control1: pt(3.38, 4.41),   control2: pt(3.66, 5.23))
        p.addCurve(to: pt(2.92, 7.58),  control1: pt(3.23, 5.99),   control2: pt(2.92, 6.71))
        p.addCurve(to: pt(6.56, 11.53), control1: pt(2.92, 10.64),  control2: pt(4.78, 11.33))
        p.addCurve(to: pt(6.05, 12.6),  control1: pt(6.33, 11.73),  control2: pt(6.12, 12.08))
        p.addCurve(to: pt(3.72, 11.94), control1: pt(5.59, 12.81),  control2: pt(4.44, 13.15))
        p.addCurve(to: pt(2.49, 11.12), control1: pt(3.57, 11.7),   control2: pt(3.12, 11.11))
        p.addCurve(to: pt(2.5, 11.65),  control1: pt(1.82, 11.13),  control2: pt(2.22, 11.5))
        p.addCurve(to: pt(3.32, 12.78), control1: pt(2.84, 11.84),  control2: pt(3.23, 12.55))
        p.addCurve(to: pt(6.01, 13.72), control1: pt(3.48, 13.23),  control2: pt(4, 14.09))
        p.addCurve(to: pt(6.02, 15.21), control1: pt(6.01, 14.39),  control2: pt(6.02, 15.02))
        p.addCurve(to: pt(5.47, 15.59), control1: pt(6.02, 15.42),  control2: pt(5.87, 15.66))
        p.addCurve(to: pt(0, 8),        control1: pt(2.29, 14.53),  control2: pt(0, 11.54))
        p.addCurve(to: pt(8, 0),        control1: pt(0, 3.58),      control2: pt(3.58, 0))
        p.closeSubpath()
        return p
    }
}

struct VersionHistoryView: View {
    let entries: [VersionEntry]
    let currentVersion: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(Loc.t("LblVersionHistory")).font(.headline)
                Spacer()
                Button("Close") { isPresented = false }
            }
            .padding(16)
            Divider()
            if entries.isEmpty {
                Spacer()
                Text("Unable to load changelog. Check your connection.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(entries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("v\(entry.version)").font(.headline)
                            if entry.version == currentVersion {
                                Text("installed")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                            Spacer()
                            Text(entry.date).font(.caption).foregroundStyle(.secondary)
                        }
                        if entry.notes.isEmpty {
                            Text("No release notes.").font(.callout).foregroundStyle(.tertiary)
                        }
                        ForEach(entry.notes, id: \.self) { note in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                Text(note).font(.callout)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(minWidth: 440, minHeight: 480)
    }
}
