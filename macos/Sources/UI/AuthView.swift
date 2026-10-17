import SwiftUI

struct AuthView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var status: AuthStatus = .idle
    @State private var token: String = ""
    @State private var pollTask: Task<Void, Never>?

    enum AuthStatus: Equatable {
        case idle, waiting, success, error(String)
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text(Loc.t("AuthTitle"))
                .font(.title2.bold())

            Text("Authorize Last.fm Scrobbler to access your Last.fm account.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            statusView

            HStack(spacing: 12) {
                Button(Loc.t("AuthOpen")) {
                    openBrowser()
                }
                .buttonStyle(.borderedProminent)
                .disabled(status == .waiting)

                if case .success = status {
                    Button("Continue") { isPresented = false }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(40)
        .frame(width: 400)
        .onDisappear { pollTask?.cancel() }
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .idle:
            Text("Click the button below to open Last.fm in your browser.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .waiting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(Loc.t("AuthWaiting"))
                    .foregroundStyle(.orange)
            }
        case .success:
            Label(Loc.t("AuthSuccess"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .error(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private var isWaiting: Bool {
        if case .waiting = status { return true }
        return false
    }

    private func openBrowser() {
        pollTask?.cancel()
        status = .waiting
        pollTask = Task {
            do {
                let client = LastFmClient()
                let (t, url) = try await client.getAuthUrl()
                token = t
                if let authUrl = URL(string: url) {
                    NSWorkspace.shared.open(authUrl)
                }
                var attempts = 0
                while attempts < 90 {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled else { return }
                    if let result = try? await client.getSession(token: token) {
                        await MainActor.run {
                            appState.settings.sessionKey = result.sessionKey
                            appState.settings.username = result.username
                            appState.isAuthenticated = true
                            appState.saveSettings()
                            status = .success
                        }
                        await appState.fetchAvatar()
                        return
                    }
                    attempts += 1
                }
                await MainActor.run { status = .error(Loc.t("AuthTimeout")) }
            } catch {
                await MainActor.run { status = .error(error.localizedDescription) }
            }
        }
    }
}
