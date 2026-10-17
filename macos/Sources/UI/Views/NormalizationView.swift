import SwiftUI

struct NormalizationView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var engine: ScrobbleEngine
    @State private var rules: [NormalizationRule] = []
    @State private var showAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            Table(rules) {
                TableColumn("") { rule in
                    Toggle("", isOn: Binding(
                        get: { rule.isEnabled },
                        set: { enabled in
                            appState.db.setRuleEnabled(id: rule.id, enabled: enabled)
                            engine.reloadRules()
                            load()
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                }
                .width(30)
                TableColumn(Loc.t("ColArtist"), value: \.field.rawValue).width(70)
                TableColumn("Description", value: \.description)
                TableColumn("Pattern", value: \.pattern)
                TableColumn("Replacement", value: \.replacement).width(100)
                TableColumn("Built-in") { rule in
                    if rule.isBuiltIn {
                        Image(systemName: "lock.fill").foregroundStyle(.secondary).font(.caption)
                    }
                }
                .width(60)
            }
            .contextMenu(forSelectionType: Int64.self) { ids in
                Button(Loc.t("BtnDeleteSelected"), role: .destructive) {
                    for id in ids {
                        appState.db.deleteRule(id: id)
                    }
                    engine.reloadRules()
                    load()
                }
            } primaryAction: { _ in }
        }
        .onAppear { load() }
        .sheet(isPresented: $showAddSheet) {
            AddRuleView(isPresented: $showAddSheet) { rule in
                appState.db.saveRule(rule)
                engine.reloadRules()
                load()
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Text(Loc.t("NavNormalization")).font(.headline)
            Spacer()
            Button(Loc.t("BtnAddRule")) { showAddSheet = true }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func load() {
        rules = appState.db.loadRules()
    }
}

struct AddRuleView: View {
    @Binding var isPresented: Bool
    let onSave: (NormalizationRule) -> Void
    @State private var field: NormalizationField = .title
    @State private var pattern = ""
    @State private var replacement = ""
    @State private var description = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Loc.t("BtnAddRule")).font(.title2.bold())

            VStack(alignment: .leading, spacing: 4) {
                Text("Field").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $field) {
                    ForEach(NormalizationField.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            inputField("Description", text: $description)
            inputField("Regex Pattern", text: $pattern)
            inputField("Replacement (empty to remove)", text: $replacement)

            HStack {
                Button("Cancel") { isPresented = false }.buttonStyle(.bordered)
                Spacer()
                Button("Add") {
                    let rule = NormalizationRule(id: -1, field: field, pattern: pattern, replacement: replacement,
                                                 isEnabled: true, description: description, isBuiltIn: false)
                    onSave(rule)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(pattern.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private func inputField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text).textFieldStyle(.roundedBorder)
        }
    }
}
