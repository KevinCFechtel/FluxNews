import SwiftUI

@MainActor
struct BackgroundSyncSettingsView: View {
    let coordinator: IOSBackgroundSyncCoordinator

    @State private var enabled = true
    @State private var loaded = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Background Sync",
                    isOn: Binding(
                        get: { enabled },
                        set: { newValue in
                            guard loaded, !isSaving else { return }
                            let previous = enabled
                            enabled = newValue
                            isSaving = true
                            errorMessage = nil
                            Task {
                                let result = await coordinator.setBackgroundSyncPreference(newValue)
                                switch result {
                                case .success:
                                    break
                                case .failure:
                                    enabled = previous
                                    errorMessage = String(localized: "Background Sync setting could not be saved. Please try again.")
                                }
                                isSaving = false
                            }
                        }
                    )
                )
                .disabled(!loaded || isSaving)
            } footer: {
                Text("When enabled, FluxNews may refresh news in the background and when you return to the app. Manual Sync remains available at all times.")
            }

            if isSaving {
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
        .navigationTitle("Background Sync")
        .task {
            guard !loaded else { return }
            let result = await coordinator.backgroundSyncPreference()
            switch result {
            case let .success(value):
                enabled = value
                loaded = true
            case .failure:
                errorMessage = String(localized: "Background Sync setting could not be loaded. Please try again.")
            }
        }
    }
}
