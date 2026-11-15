import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var store: NewsreaderStore
    @ObservedObject var bootstrapper: CoreBootstrapper
    @ObservedObject var articleListActionPreferences: IOSArticleListActionPreferences
    let onDiagnostics: () -> Void

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    AccountConfigurationView(bootstrapper: bootstrapper, allowsRemoval: true, embedded: true)
                } label: {
                    Label("Account", systemImage: "person.crop.circle")
                }
                NavigationLink {
                    ArticlesSettingsView(store: store, bootstrapper: bootstrapper)
                } label: {
                    Label("Articles", systemImage: "doc.text")
                }
                NavigationLink {
                    ArticleListActionsSettingsView(
                        preferences: articleListActionPreferences
                    )
                } label: {
                    Label("Action Bar", systemImage: "rectangle.bottomthird.inset.filled")
                }
                NavigationLink {
                    NavigationSettingsView(store: store)
                } label: {
                    Label("Navigation", systemImage: "sidebar.leading")
                }
                NavigationLink {
                    IOSMediaSettingsView(
                        bootstrapper: bootstrapper,
                        onPolicyChanged: {
                            await IOSAppRuntime.shared
                                .mediaTransferReconciliationHandoff
                                .requestReconciliation()
                        }
                    )
                } label: {
                    Label("Media", systemImage: "headphones")
                }
                NavigationLink {
                    DownloadedDataSettingsView(
                        bootstrapper: bootstrapper,
                        transferCoordinator: IOSAppRuntime.shared.mediaRuntime.transferCoordinator,
                        onDeletionRequested: {
                            await IOSAppRuntime.shared
                                .mediaTransferReconciliationHandoff
                                .requestReconciliation()
                        }
                    )
                } label: {
                    Label("Downloaded Data", systemImage: "internaldrive")
                }
                NavigationLink {
                    BackgroundSyncSettingsView(
                        coordinator: IOSAppRuntime.shared.backgroundSyncCoordinator
                    )
                } label: {
                    Label("Background Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                NavigationLink {
                    ConfigurationBackupSettingsView(
                        store: store,
                        bootstrapper: bootstrapper,
                        articleListActionPreferences: articleListActionPreferences
                    )
                } label: {
                    Label("Configuration Backup", systemImage: "externaldrive.badge.timemachine")
                }
                NavigationLink {
                    SupportDiagnosticsSettingsView()
                } label: {
                    Label("Support Diagnostics", systemImage: "waveform.path.ecg")
                }
                NavigationLink {
                    AboutSettingsView()
                } label: {
                    Label("About", systemImage: "info.circle")
                }
#if DEBUG || FLUX_PERFORMANCE_DIAGNOSTICS
                Button { onDiagnostics() } label: {
                    Label("Developer Diagnostics", systemImage: "stethoscope")
                }
#endif
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}


enum IOSAboutInformation {
    static let fluxNewsRepositoryURL =
        URL(string: "https://github.com/KevinCFechtel/FluxNews")!
    static let fluxRepositoryURL =
        URL(string: "https://github.com/KevinCFechtel/Flux")!
    static let minifluxProjectURL =
        URL(string: "https://miniflux.app")!
    static let licenseURL =
        URL(string: "https://github.com/KevinCFechtel/FluxNews/blob/main/LICENSE")!

    static func version(from infoDictionary: [String: Any]) -> String {
        nonEmptyString(
            infoDictionary["CFBundleShortVersionString"]
        ) ?? String(localized: "Unknown")
    }

    static func build(from infoDictionary: [String: Any]) -> String {
        nonEmptyString(
            infoDictionary["CFBundleVersion"]
        ) ?? String(localized: "Unknown")
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct AboutSettingsView: View {
    private let infoDictionary: [String: Any]

    init(bundle: Bundle = .main) {
        infoDictionary = bundle.infoDictionary ?? [:]
    }

    var body: some View {
        List {
            Section {
                LabeledContent(
                    "Version",
                    value: IOSAboutInformation.version(from: infoDictionary)
                )
                LabeledContent(
                    "Build",
                    value: IOSAboutInformation.build(from: infoDictionary)
                )
            } header: {
                Text("Flux News")
            } footer: {
                Text("© 2023 Kevin Fechtel")
            }

            Section {
                Link(destination: IOSAboutInformation.fluxNewsRepositoryURL) {
                    Label(
                        "FluxNews Repository",
                        systemImage: "chevron.left.forwardslash.chevron.right"
                    )
                }
                Link(destination: IOSAboutInformation.fluxRepositoryURL) {
                    Label(
                        "Flux Development Repository",
                        systemImage: "shippingbox"
                    )
                }
                Link(destination: IOSAboutInformation.licenseURL) {
                    Label("BSD 3-Clause License", systemImage: "doc.text")
                }
            } header: {
                Text("Open Source")
            } footer: {
                Text(
                    "Flux News is open source. The application project is moving to the FluxNews repository; the Flux repository remains available for the current native development history and shared Core."
                )
            }

            Section {
                Text(
                    "Flux News is a newsreader and podcast client for the Miniflux backend."
                )
                Link(destination: IOSAboutInformation.minifluxProjectURL) {
                    Label("Miniflux Project", systemImage: "safari")
                }
            } header: {
                Text("Miniflux")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}


enum IOSAppLogLevelFilter: String, CaseIterable, Identifiable {
    case all
    case trace
    case debug
    case info
    case warning
    case error

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .trace: String(localized: "Trace")
        case .debug: String(localized: "Debug")
        case .info: String(localized: "Info")
        case .warning: String(localized: "Warning")
        case .error: String(localized: "Error")
        }
    }

    var level: IOSAppLogLevel? {
        switch self {
        case .all: nil
        case .trace: .trace
        case .debug: .debug
        case .info: .info
        case .warning: .warning
        case .error: .error
        }
    }
}


enum IOSAppLogViewerProjection {
    static func visibleEntries(
        from entries: [IOSAppLogEntry],
        levelFilter: IOSAppLogLevelFilter,
        searchText: String
    ) -> [IOSAppLogEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries
            .filter { entry in
                guard let level = levelFilter.level else { return true }
                return entry.level == level
            }
            .filter { entry in
                guard !query.isEmpty else { return true }
                return entry.category.localizedCaseInsensitiveContains(query)
                    || entry.message.localizedCaseInsensitiveContains(query)
            }
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp > rhs.timestamp
                }
                return lhs.id.uuidString > rhs.id.uuidString
            }
    }

    static func recordText(_ entry: IOSAppLogEntry) -> String {
        let formatter = ISO8601DateFormatter()
        return "\(formatter.string(from: entry.timestamp)) [\(entry.level.exportLabel)] [\(entry.category)] \(entry.message)"
    }
}


struct SupportDiagnosticsSettingsView: View {
    private let diagnostics: IOSAppDiagnostics

    @State private var debugLoggingEnabled: Bool
    @State private var records: [IOSAppLogEntry]
    @State private var diagnosticsExportURL: URL?
    @State private var diagnosticsExportError: String?
    @State private var clearConfirmationPresented = false

    init(diagnostics: IOSAppDiagnostics = .shared) {
        self.diagnostics = diagnostics
        _debugLoggingEnabled = State(
            initialValue: diagnostics.isDebugLoggingEnabled
        )
        _records = State(initialValue: diagnostics.snapshot())
    }

    var body: some View {
        List {
            Section {
                Toggle("Debug Logging", isOn: Binding(
                    get: { debugLoggingEnabled },
                    set: { enabled in
                        diagnostics.setDebugLoggingEnabled(enabled)
                        refresh()
                    }
                ))

                LabeledContent("Stored Records", value: "\(records.count)")

                NavigationLink {
                    IOSAppLogViewerView(diagnostics: diagnostics)
                } label: {
                    Label("Log Viewer", systemImage: "doc.text.magnifyingglass")
                }
            } header: {
                Text("Logging")
            } footer: {
                Text("Info, warning and error records are kept even when Debug Logging is off. Debug and trace records are stored only while Debug Logging is enabled.")
            }

            Section {
                Button {
                    prepareDiagnosticsExport()
                } label: {
                    Label(
                        "Prepare Diagnostics Export",
                        systemImage: "doc.badge.gearshape"
                    )
                }

                if let diagnosticsExportURL {
                    ShareLink(item: diagnosticsExportURL) {
                        Label(
                            "Export Diagnostics",
                            systemImage: "square.and.arrow.up"
                        )
                    }
                }

                if let diagnosticsExportError {
                    Text(diagnosticsExportError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Support Export")
            } footer: {
                Text("The export contains the retained native and Core support records plus app, OS, device and Debug Logging metadata.")
            }

            Section {
                Button("Clear Logs", role: .destructive) {
                    clearConfirmationPresented = true
                }
            } footer: {
                Text("Support logs are stored locally with bounded retention. Credentials and registered custom-header values are redacted before records are persisted or exported.")
            }
        }
        .navigationTitle("Support Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        .alert("Clear Logs?", isPresented: $clearConfirmationPresented) {
            Button("Clear Logs", role: .destructive) {
                diagnostics.clear()
                diagnosticsExportURL = nil
                diagnosticsExportError = nil
                refresh()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the retained local support log. New records will continue to be collected according to the current logging settings.")
        }
    }

    private func refresh() {
        debugLoggingEnabled = diagnostics.isDebugLoggingEnabled
        records = diagnostics.snapshot()
    }

    private func prepareDiagnosticsExport() {
        do {
            diagnosticsExportURL = try diagnostics.makeExportURL()
            diagnosticsExportError = nil
        } catch {
            diagnosticsExportURL = nil
            diagnosticsExportError = String(
                localized: "The diagnostics export could not be prepared."
            )
        }
        refresh()
    }
}


struct IOSAppLogViewerView: View {
    private let diagnostics: IOSAppDiagnostics

    @State private var records: [IOSAppLogEntry]
    @State private var levelFilter: IOSAppLogLevelFilter = .all
    @State private var searchText = ""

    init(diagnostics: IOSAppDiagnostics = .shared) {
        self.diagnostics = diagnostics
        _records = State(initialValue: diagnostics.snapshot())
    }

    private var visibleRecords: [IOSAppLogEntry] {
        IOSAppLogViewerProjection.visibleEntries(
            from: records,
            levelFilter: levelFilter,
            searchText: searchText
        )
    }

    var body: some View {
        List {
            Section {
                Picker("Level", selection: $levelFilter) {
                    ForEach(IOSAppLogLevelFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
            }

            if visibleRecords.isEmpty {
                ContentUnavailableView(
                    "No Log Records",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(
                        searchText.isEmpty
                            ? "No retained records match the selected level."
                            : "No retained records match the selected level and search."
                    )
                )
            } else {
                Section {
                    ForEach(visibleRecords) { entry in
                        IOSAppLogEntryRow(entry: entry)
                    }
                } footer: {
                    Text("\(visibleRecords.count) visible records")
                }
            }
        }
        .navigationTitle("Log Viewer")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            prompt: "Search category or message"
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: reload) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        records = diagnostics.snapshot()
    }
}


private struct IOSAppLogEntryRow: View {
    let entry: IOSAppLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(
                    entry.timestamp,
                    format: .dateTime
                        .year()
                        .month()
                        .day()
                        .hour()
                        .minute()
                        .second()
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Text(entry.level.exportLabel)
                    .font(.caption.weight(.semibold))

                Button {
                    UIPasteboard.general.string =
                        IOSAppLogViewerProjection.recordText(entry)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy Log Record")
            }

            Text(entry.category)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            Text(entry.message)
                .textSelection(.enabled)
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string =
                    IOSAppLogViewerProjection.recordText(entry)
            } label: {
                Label("Copy Log Record", systemImage: "doc.on.doc")
            }
        }
    }
}
