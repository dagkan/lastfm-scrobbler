import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var engine: ScrobbleEngine
    @State private var records: [ScrobbleRecord] = []
    @State private var selected: ScrobbleRecord?
    @State private var showEditSheet = false
    @State private var showManualSheet = false
    @State private var searchText = ""

    var filtered: [ScrobbleRecord] {
        guard !searchText.isEmpty else { return records }
        return records.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.artist.localizedCaseInsensitiveContains(searchText) ||
            $0.album.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if records.isEmpty {
                emptyState
            } else {
                historyList
            }
        }
        .onAppear { load() }
        .sheet(isPresented: $showEditSheet) {
            if let rec = selected {
                EditTrackView(record: rec) { artist, title, album in
                    appState.db.updateScrobbleRecord(id: rec.id, artist: artist, title: title, album: album)
                    Task { await engine.manualScrobble(title: title, artist: artist, album: album, timestamp: rec.scrobbledAt) }
                    load()
                }
            }
        }
        .sheet(isPresented: $showManualSheet) {
            ManualScrobbleView(isPresented: $showManualSheet)
                .environmentObject(appState)
                .environmentObject(engine)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search…", text: $searchText)
                .textFieldStyle(.plain)
            Spacer()
            Button(Loc.t("BtnManualScrobble")) { showManualSheet = true }
                .buttonStyle(.bordered)
            Button(Loc.t("BtnExport")) { exportCSV() }
                .buttonStyle(.bordered)
            Button(Loc.t("BtnImport")) { importCSV() }
                .buttonStyle(.bordered)
            Button(Loc.t("BtnRefresh")) { load() }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var historyList: some View {
        Table(filtered) {
            TableColumn(Loc.t("ColTime")) { rec in
                Text(shortDate(rec.scrobbledAt))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .width(90)
            TableColumn(Loc.t("ColArtist")) { rec in Text(rec.artist).lineLimit(1) }
            TableColumn(Loc.t("ColTrack")) { rec in Text(rec.title).lineLimit(1) }
            TableColumn(Loc.t("ColAlbum")) { rec in Text(rec.album).lineLimit(1) }
            TableColumn(Loc.t("ColStatus")) { rec in
                Label(rec.success ? "OK" : "Failed",
                      systemImage: rec.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(rec.success ? .green : .red)
                    .font(.caption)
            }
            .width(80)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No scrobbles yet")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() {
        records = appState.db.loadHistory()
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "scrobbles.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        if panel.runModal() == .OK, let url = panel.url {
            try? appState.db.exportToCSV(path: url.path)
        }
    }

    private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        if panel.runModal() == .OK, let url = panel.url {
            if let result = try? appState.db.importFromCSV(path: url.path) {
                load()
                let alert = NSAlert()
                alert.messageText = "Import complete"
                alert.informativeText = "Imported: \(result.imported), Skipped: \(result.skipped)"
                alert.runModal()
            }
        }
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f.string(from: date)
    }
}

struct EditTrackView: View {
    let record: ScrobbleRecord
    let onSave: (String, String, String) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var artist: String
    @State private var title: String
    @State private var album: String

    init(record: ScrobbleRecord, onSave: @escaping (String, String, String) -> Void) {
        self.record = record
        self.onSave = onSave
        _artist = State(initialValue: record.artist)
        _title = State(initialValue: record.title)
        _album = State(initialValue: record.album)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Loc.t("EditTrack")).font(.title2.bold())
            field("Title", text: $title)
            field("Artist", text: $artist)
            field("Album", text: $album)
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.bordered)
                Spacer()
                Button("Save & Rescrobble") {
                    onSave(artist, title, album)
                    dismiss()
                }.buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct ManualScrobbleView: View {
    @EnvironmentObject var engine: ScrobbleEngine
    @Binding var isPresented: Bool
    @State private var title = ""
    @State private var artist = ""
    @State private var album = ""
    @State private var timestamp = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Loc.t("ManualScrobble")).font(.title2.bold())
            field("Title *", text: $title)
            field("Artist *", text: $artist)
            field("Album", text: $album)
            DatePicker("Time", selection: $timestamp)
                .datePickerStyle(.field)
            HStack {
                Button("Cancel") { isPresented = false }.buttonStyle(.bordered)
                Spacer()
                Button("Scrobble") {
                    guard !title.isEmpty, !artist.isEmpty else { return }
                    Task {
                        await engine.manualScrobble(title: title, artist: artist, album: album, timestamp: timestamp)
                        isPresented = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty || artist.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text).textFieldStyle(.roundedBorder)
        }
    }
}
