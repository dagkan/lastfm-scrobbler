import AppKit
import SwiftUI
import Combine

@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var appState: AppState
    private var mainWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var hotkeyManager = HotkeyManager()

    init(appState: AppState) {
        self.appState = appState
        super.init()
        setupStatusItem()
        setupHotkeys()
        observeEngine()

        if !appState.isAuthenticated {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showMainWindow()
            }
        }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemTitle(nil)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        buildMenu()
    }

    private func updateStatusItemTitle(_ track: Track?) {
        if let t = track {
            let text = "♪ \(t.artist) – \(t.title)"
            let truncated = text.count > 63 ? String(text.prefix(60)) + "…" : text
            statusItem.button?.title = truncated
        } else {
            statusItem.button?.title = "Last.fm"
        }
    }

    private func buildMenu() {
        let menu = NSMenu()

        let monitorItem = NSMenuItem(title: Loc.t("BtnOpenMonitor"), action: #selector(showMainWindow), keyEquivalent: "")
        monitorItem.target = self
        menu.addItem(monitorItem)

        if appState.isAuthenticated {
            let profileItem = NSMenuItem(title: Loc.t("BtnVisitProfile"), action: #selector(visitProfile), keyEquivalent: "")
            profileItem.target = self
            menu.addItem(profileItem)

            let logoutItem = NSMenuItem(title: Loc.t("LogOut"), action: #selector(logOut), keyEquivalent: "")
            logoutItem.target = self
            menu.addItem(logoutItem)
        }

        menu.addItem(.separator())

        let hk = appState.settings.enableGlobalHotkeys
        let loveItem = NSMenuItem(title: hk ? "\(Loc.t("BtnLove")) (⌃⌥L)" : Loc.t("BtnLove"), action: #selector(loveCurrentTrack), keyEquivalent: "")
        loveItem.target = self
        menu.addItem(loveItem)

        let copyItem = NSMenuItem(title: hk ? "\(Loc.t("BtnCopyNowPlaying")) (⌃⌥C)" : Loc.t("BtnCopyNowPlaying"), action: #selector(copyNowPlaying), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        menu.addItem(.separator())

        let updatesItem = NSMenuItem(title: Loc.t("BtnCheckForUpdates"), action: #selector(checkForUpdates), keyEquivalent: "")
        updatesItem.target = self
        menu.addItem(updatesItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: Loc.t("BtnExit"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Hotkeys

    /// Opt-in (Settings › Advanced): global monitors need the Accessibility
    /// permission and ⌃⌥ combos collide with some keyboard layouts.
    private func setupHotkeys() {
        hotkeyManager.removeAll()
        guard appState.settings.enableGlobalHotkeys else { return }
        hotkeyManager.register(key: "l", modifiers: [.control, .option]) { [weak self] in
            Task { await self?.appState.engine.loveTrack() }
        }
        hotkeyManager.register(key: "c", modifiers: [.control, .option]) { [weak self] in
            self?.copyNowPlaying()
        }
    }

    // MARK: - Observe Engine

    private func observeEngine() {
        appState.engine.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in self?.updateStatusItemTitle(track) }
            .store(in: &cancellables)

        appState.engine.$sessionScrobbleCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.buildMenu() }
            .store(in: &cancellables)

        appState.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.buildMenu() }
            .store(in: &cancellables)

        appState.$settings
            .map(\.enableGlobalHotkeys)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.setupHotkeys(); self?.buildMenu() }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc func statusItemClicked() { showMainWindow() }

    @objc func showMainWindow() {
        if mainWindow == nil { createMainWindow() }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func loveCurrentTrack() {
        Task { await appState.engine.loveTrack() }
    }

    @objc func copyNowPlaying() {
        if let text = appState.engine.getNowPlayingString() {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    @objc func visitProfile() {
        let username = appState.settings.username
        if let url = URL(string: "https://www.last.fm/user/\(username)") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func logOut() {
        appState.logOut()
        buildMenu()
    }

    @objc func checkForUpdates() {
        Task {
            if let info = try? await appState.engine.checkForUpdates() {
                await MainActor.run {
                    showUpdateAlert(info: info)
                }
            } else {
                await MainActor.run { showUpToDateAlert() }
            }
        }
    }

    @objc func quitApp() {
        appState.engine.stop()
        NSApp.terminate(nil)
    }

    // MARK: - Main Window

    private func createMainWindow() {
        let contentView = MainWindowView()
            .environmentObject(appState)
            .environmentObject(appState.engine)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Last.fm Scrobbler"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.setFrameAutosaveName("MainWindow")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 520)
        mainWindow = window
    }

    // MARK: - Alerts

    private func showUpdateAlert(info: UpdateInfo) {
        let alert = NSAlert()
        alert.messageText = "\(Loc.t("UpdateAvailable")) — v\(info.version)"
        let notes = info.releaseNotes.map { "•  \($0)" }.joined(separator: "\n")
        alert.informativeText = notes.isEmpty
            ? "You're on v\(UpdateChecker().currentVersion)."
            : "You're on v\(UpdateChecker().currentVersion).\n\n\(notes)"
        alert.addButton(withTitle: Loc.t("Download"))
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            Task {
                do {
                    let dmg = try await UpdateChecker().download(info: info)
                    NSWorkspace.shared.open(dmg)
                } catch {
                    let err = NSAlert()
                    err.messageText = "Download failed"
                    err.informativeText = error.localizedDescription
                    err.runModal()
                }
            }
        }
    }

    private func showUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = Loc.t("UpToDate")
        alert.informativeText = "You have the latest version (\(UpdateChecker().currentVersion))."
        alert.runModal()
    }
}
