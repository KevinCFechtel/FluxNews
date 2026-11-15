import SwiftUI

private enum IOSDownloadRetentionChoice: String, CaseIterable, Identifiable {
    case forever
    case days7
    case days30
    case days90

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .forever: "Forever"
        case .days7: "7 days"
        case .days30: "30 days"
        case .days90: "90 days"
        }
    }

    var coreValue: DownloadRetention {
        switch self {
        case .forever: .forever
        case .days7: .days(days: 7)
        case .days30: .days(days: 30)
        case .days90: .days(days: 90)
        }
    }

    static func from(_ value: DownloadRetention) -> Self {
        switch value {
        case .forever:
            .forever
        case let .days(days):
            switch days {
            case 7: .days7
            case 30: .days30
            case 90: .days90
            default: .forever
            }
        }
    }
}

struct IOSMediaSettingsView: View {
    @ObservedObject var bootstrapper: CoreBootstrapper
    let onPolicyChanged: () async -> Void

    @State private var networkPolicy: DownloadNetworkPolicy = .anyNetwork
    @State private var retention: IOSDownloadRetentionChoice = .forever
    @State private var deleteAfterPlayback = false
    @State private var autoDownloadListeningList = false
    @State private var removeCompletedListeningList = false
    @State private var loaded = false
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if loaded {
                Section {
                    Picker(
                        "Download Network",
                        selection: Binding(
                            get: { networkPolicy },
                            set: updateNetworkPolicy
                        )
                    ) {
                        Text("Any Network")
                            .tag(DownloadNetworkPolicy.anyNetwork)
                        Text("Unmetered Networks Only")
                            .tag(DownloadNetworkPolicy.unmeteredOnly)
                    }

                    Picker(
                        "Keep Downloads",
                        selection: Binding(
                            get: { retention },
                            set: updateRetention
                        )
                    ) {
                        ForEach(IOSDownloadRetentionChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                } header: {
                    Text("Downloads")
                } footer: {
                    Text(
                        "Automatic and manual downloads use the same network policy. Retention cleanup applies to downloaded media that is no longer protected by active playback or other Core media state."
                    )
                }

                Section {
                    Toggle(
                        "Automatically download Listening List audio",
                        isOn: Binding(
                            get: { autoDownloadListeningList },
                            set: updateAutoDownloadListeningList
                        )
                    )
                    Toggle(
                        "Delete download after playback completes",
                        isOn: Binding(
                            get: { deleteAfterPlayback },
                            set: updateDeleteAfterPlayback
                        )
                    )
                    Toggle(
                        "Remove completed items from Listening List",
                        isOn: Binding(
                            get: { removeCompletedListeningList },
                            set: updateRemoveCompletedListeningList
                        )
                    )
                } header: {
                    Text("Listening List")
                }
                .disabled(saving)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }

            if saving {
                Section {
                    HStack {
                        ProgressView()
                        Text("Saving…")
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Media")
        .task {
            await load()
        }
    }

    private func load() async {
        let result = await bootstrapper.mediaSettings()
        switch result {
        case let .success(settings):
            networkPolicy = settings.downloadNetworkPolicy
            retention = IOSDownloadRetentionChoice.from(
                settings.downloadRetention
            )
            deleteAfterPlayback = settings.deleteAfterPlayback
            autoDownloadListeningList = settings.autoDownloadListeningList
            removeCompletedListeningList =
                settings.removeCompletedListeningList
            errorMessage = nil
            loaded = true
        case .failure:
            errorMessage = String(
                localized: "Media settings could not be loaded. Please try again."
            )
        }
    }

    private func updateNetworkPolicy(_ value: DownloadNetworkPolicy) {
        let previous = networkPolicy
        networkPolicy = value
        save(previous: { networkPolicy = previous }) {
            await bootstrapper.setDownloadNetworkPolicyPreference(value)
        }
    }

    private func updateRetention(_ value: IOSDownloadRetentionChoice) {
        let previous = retention
        retention = value
        save(previous: { retention = previous }) {
            await bootstrapper.setDownloadRetentionPreference(value.coreValue)
        }
    }

    private func updateDeleteAfterPlayback(_ value: Bool) {
        let previous = deleteAfterPlayback
        deleteAfterPlayback = value
        save(previous: { deleteAfterPlayback = previous }) {
            await bootstrapper.setDeleteAfterPlaybackPreference(value)
        }
    }

    private func updateAutoDownloadListeningList(_ value: Bool) {
        let previous = autoDownloadListeningList
        autoDownloadListeningList = value
        save(previous: { autoDownloadListeningList = previous }) {
            await bootstrapper.setAutoDownloadListeningListPreference(value)
        }
    }

    private func updateRemoveCompletedListeningList(_ value: Bool) {
        let previous = removeCompletedListeningList
        removeCompletedListeningList = value
        save(previous: { removeCompletedListeningList = previous }) {
            await bootstrapper
                .setRemoveCompletedListeningListPreference(value)
        }
    }

    private func save(
        previous rollback: @escaping @MainActor () -> Void,
        operation: @escaping @MainActor () async -> Result<Void, Error>
    ) {
        guard !saving else {
            rollback()
            return
        }
        saving = true
        errorMessage = nil
        Task { @MainActor in
            let result = await operation()
            switch result {
            case .success:
                await onPolicyChanged()
            case .failure:
                rollback()
                errorMessage = String(
                    localized: "Media setting could not be saved. Please try again."
                )
            }
            saving = false
        }
    }
}


struct DownloadedDataSettingsView: View {
    @ObservedObject var bootstrapper: CoreBootstrapper
    @ObservedObject var transferCoordinator: IOSMediaTransferCoordinator
    let onDeletionRequested: () async -> Void

    @State private var summary = DownloadedMediaSummary(
        fileCount: 0,
        totalSizeBytes: 0
    )
    @State private var loaded = false
    @State private var deleting = false
    @State private var confirmationPresented = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                LabeledContent("Downloaded Files") {
                    Text(summary.fileCount, format: .number)
                }
                LabeledContent("Storage Used") {
                    Text(Self.formatBytes(summary.totalSizeBytes))
                }
            } footer: {
                Text(
                    "This includes local audio files that are still waiting for physical deletion. Listening List items and playback progress are stored separately."
                )
            }

            Section {
                Button("Delete All Downloads", role: .destructive) {
                    confirmationPresented = true
                }
                .disabled(!loaded || deleting || summary.fileCount == 0)

                if deleting {
                    HStack {
                        ProgressView()
                        Text("Deleting Downloads…")
                    }
                }
            } footer: {
                Text(
                    "Deleting downloads removes only local media files. Listening List items and playback progress are kept."
                )
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Downloaded Data")
        .overlay {
            if !loaded {
                ProgressView()
            }
        }
        .refreshable {
            await load()
        }
        .task {
            await load()
        }
        .onChange(of: transferCoordinator.workRevision) {
            Task { await load() }
        }
        .alert("Delete All Downloads?", isPresented: $confirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteAll() }
            }
        } message: {
            Text(
                "All locally downloaded audio files will be removed. Listening List items and playback progress will not be deleted."
            )
        }
    }

    private func load() async {
        let result = await bootstrapper.downloadedMediaSummary()
        switch result {
        case let .success(summary):
            self.summary = summary
            errorMessage = nil
            loaded = true
        case .failure:
            errorMessage = String(
                localized: "Downloaded data could not be loaded. Please try again."
            )
            loaded = true
        }
    }

    private func deleteAll() async {
        guard !deleting else { return }
        deleting = true
        errorMessage = nil

        let result = await bootstrapper.requestAllDownloadDeletions()
        switch result {
        case .success:
            await onDeletionRequested()
            await load()
        case .failure:
            errorMessage = String(
                localized: "Downloads could not be deleted. Please try again."
            )
        }
        deleting = false
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(clamping: bytes),
            countStyle: .file
        )
    }
}
