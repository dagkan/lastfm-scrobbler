import SwiftUI
import AppKit

@main
struct LastFmScrobblerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    private var statusBarController: StatusBarController?
    private var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard !isAnotherInstanceRunning() else { NSApp.terminate(nil); return }

        Telemetry.installCrashHandlers()

        let state = AppState()
        self.appState = state

        let controller = StatusBarController(appState: state)
        self.statusBarController = controller

        Task { @MainActor in
            await state.start()
            Telemetry.ping()
        }
    }

    private func isAnotherInstanceRunning() -> Bool {
        guard let bundleId = Bundle.main.bundleIdentifier else { return false }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        return apps.contains { $0 != NSRunningApplication.current }
    }
}
