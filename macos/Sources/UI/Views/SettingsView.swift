import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var settings: AppSettings = AppSettings()
    @State private var showAuthSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                accountSection
                scrobbleSection
                behaviorSection
                webhookSection
                advancedSection
            }
            .padding(20)
        }
        .background(Color(nsColor: NSColor(red: 0.094, green: 0.094, blue: 0.094, alpha: 1)))
        .onAppear { settings = appState.settings }
        .sheet(isPresented: $showAuthSheet) {
            AuthView(isPresented: $showAuthSheet)
                .environmentObject(appState)
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        section(title: "Account") {
            if appState.isAuthenticated {
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: appState.avatarUrl)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Loc.t("SignedInAs")).font(.caption).foregroundStyle(.secondary)
                        Text(appState.settings.username).font(.headline)
                    }

                    Spacer()

                    Button {
                        if let url = URL(string: "https://www.last.fm/user/\(appState.settings.username)") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("Profile", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)

                    Button(Loc.t("LogOut")) {
                        appState.logOut()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                }
            } else {
                HStack {
                    Text("Not connected").foregroundStyle(.secondary)
                    Spacer()
                    Button(Loc.t("LogIn")) { showAuthSheet = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    // MARK: - Scrobble Thresholds

    private var scrobbleSection: some View {
        section(title: Loc.t("NavScrobbling")) {
            VStack(spacing: 12) {
                row(label: Loc.t("LblThreshold")) {
                    HStack {
                        Slider(value: Binding(
                            get: { Double(settings.scrobbleThresholdPercent) },
                            set: { settings.scrobbleThresholdPercent = Int($0) }
                        ), in: 10...90, step: 5)
                        Text("\(settings.scrobbleThresholdPercent)%")
                            .frame(width: 40)
                            .monospacedDigit()
                    }
                }
                row(label: Loc.t("LblMaximum")) {
                    HStack {
                        Stepper("\(settings.scrobbleThresholdMaxSeconds)s",
                                value: Binding(
                                    get: { settings.scrobbleThresholdMaxSeconds },
                                    set: { settings.scrobbleThresholdMaxSeconds = $0 }
                                ), in: 60...600, step: 30)
                    }
                }
                row(label: Loc.t("LblMinimum")) {
                    Stepper("\(settings.scrobbleMinSeconds)s",
                            value: Binding(
                                get: { settings.scrobbleMinSeconds },
                                set: { settings.scrobbleMinSeconds = $0 }
                            ), in: 10...120, step: 5)
                }
                row(label: Loc.t("LblDuplicateProtection")) {
                    HStack {
                        Stepper("\(settings.duplicateWindowMinutes) min",
                                value: Binding(
                                    get: { settings.duplicateWindowMinutes },
                                    set: { settings.duplicateWindowMinutes = $0 }
                                ), in: 0...60, step: 1)
                    }
                }
                row(label: Loc.t("DailyGoal")) {
                    Stepper(settings.dailyScrobbleGoal == 0 ? "Off" : "\(settings.dailyScrobbleGoal)",
                            value: Binding(
                                get: { settings.dailyScrobbleGoal },
                                set: { settings.dailyScrobbleGoal = $0 }
                            ), in: 0...500, step: 10)
                }
            }
        }
    }

    // MARK: - Behavior

    private var behaviorSection: some View {
        section(title: "Behavior") {
            VStack(spacing: 8) {
                toggle(Loc.t("FilterAppleOnly"), binding: Binding(
                    get: { settings.filterAppleMusicOnly },
                    set: { settings.filterAppleMusicOnly = $0 }
                ))
                toggle(Loc.t("AutoNormalize"), binding: Binding(
                    get: { settings.autoNormalize },
                    set: { settings.autoNormalize = $0 }
                ))
                toggle(Loc.t("EditBeforeScrobble"), binding: Binding(
                    get: { settings.editBeforeScrobble },
                    set: { settings.editBeforeScrobble = $0 }
                ))
                toggle(Loc.t("ShowNotification"), binding: Binding(
                    get: { settings.showNowPlayingNotification },
                    set: { settings.showNowPlayingNotification = $0 }
                ))
                toggle(Loc.t("StartAtLogin"), binding: Binding(
                    get: { settings.startAtLogin },
                    set: { v in settings.startAtLogin = v; applyLoginItem(v) }
                ))

                row(label: Loc.t("LblAccentColor")) {
                    HStack {
                        ColorPicker("", selection: Binding(
                            get: { Color(hex: settings.accentColor) ?? .red },
                            set: { settings.accentColor = $0.hexString }
                        ))
                        .labelsHidden()
                        Text(settings.accentColor)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                row(label: Loc.t("LblLanguage")) {
                    Picker("", selection: Binding(
                        get: { settings.language },
                        set: { settings.language = $0 }
                    )) {
                        Text("English").tag("en")
                        Text("Türkçe").tag("tr")
                        Text("Français").tag("fr")
                        Text("Deutsch").tag("de")
                        Text("Español").tag("es")
                        Text("Português").tag("pt")
                        Text("Italiano").tag("it")
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
            }

            HStack {
                Spacer()
                Button("Save") {
                    appState.settings = settings
                    appState.saveSettings()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Webhook

    private var webhookSection: some View {
        section(title: Loc.t("LblWebhook")) {
            VStack(spacing: 8) {
                TextField("https://example.com/webhook", text: Binding(
                    get: { settings.webhookUrl },
                    set: { settings.webhookUrl = $0 }
                ))
                .textFieldStyle(.roundedBorder)

                toggle("On Scrobble", binding: Binding(
                    get: { settings.webhookOnScrobble },
                    set: { settings.webhookOnScrobble = $0 }
                ))
                toggle("On Now Playing", binding: Binding(
                    get: { settings.webhookOnNowPlaying },
                    set: { settings.webhookOnNowPlaying = $0 }
                ))
            }
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        section(title: Loc.t("SectionAdvanced")) {
            VStack(alignment: .leading, spacing: 8) {
                toggle(Loc.t("ChkHotkeys"), binding: Binding(
                    get: { settings.enableGlobalHotkeys },
                    set: { settings.enableGlobalHotkeys = $0 }
                ))
                Text(Loc.t("HotkeysHint"))
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                toggle(Loc.t("ChkTelemetry"), binding: Binding(
                    get: { settings.telemetryEnabled },
                    set: { settings.telemetryEnabled = $0 }
                ))
                Text(Loc.t("TelemetryHint"))
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Save") {
                    appState.settings = settings
                    appState.saveSettings()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Helpers

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(16)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
        }
    }

    private func row<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).font(.callout)
            Spacer()
            content()
        }
    }

    private func toggle(_ label: String, binding: Binding<Bool>) -> some View {
        Toggle(label, isOn: binding)
            .toggleStyle(.switch)
            .controlSize(.small)
    }

    private func applyLoginItem(_ enable: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enable {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Silently ignore — requires user approval in System Preferences
            }
        }
    }
}

extension Color {
    var hexString: String {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return "#BA0000" }
        let r = Int(components.redComponent * 255)
        let g = Int(components.greenComponent * 255)
        let b = Int(components.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
