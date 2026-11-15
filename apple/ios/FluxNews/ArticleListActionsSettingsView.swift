import SwiftUI

struct ArticleListActionsSettingsView: View {
    @Environment(\.editMode) private var editMode
    @ObservedObject var preferences: IOSArticleListActionPreferences

    private var isEditing: Bool {
        editMode?.wrappedValue.isEditing == true
    }

    private var availableActions: [IOSBottomAction] {
        IOSBottomAction.configurableActions.filter {
            !preferences.actions.contains($0)
        }
    }

    var body: some View {
        List {
            Section {
                LabeledContent {
                    Text("Always shown")
                        .foregroundStyle(.secondary)
                } label: {
                    Label(
                        IOSBottomAction.sync.settingsTitle,
                        systemImage: IOSBottomAction.sync.symbolName
                    )
                }

                ForEach(preferences.actions) { action in
                    Label(action.settingsTitle, systemImage: action.symbolName)
                }
                .onDelete { offsets in
                    guard isEditing else { return }
                    var actions = preferences.actions
                    actions.remove(atOffsets: offsets)
                    preferences.setActions(actions)
                }
                .onMove { source, destination in
                    guard isEditing else { return }
                    var actions = preferences.actions
                    actions.move(fromOffsets: source, toOffset: destination)
                    preferences.setActions(actions)
                }
                .deleteDisabled(!isEditing)
                .moveDisabled(!isEditing)

                LabeledContent {
                    Text("Always available")
                        .foregroundStyle(.secondary)
                } label: {
                    Label(
                        IOSBottomAction.more.settingsTitle,
                        systemImage: IOSBottomAction.more.symbolName
                    )
                }
            } header: {
                Text("Article List Actions")
            } footer: {
                Text("Sync stays fixed at the beginning and More stays available as the fallback. The order of selected actions sets their display priority. Use Edit to remove or reorder selected actions.")
            }

            if !availableActions.isEmpty {
                Section {
                    ForEach(availableActions) { action in
                        Button {
                            preferences.setActions(preferences.actions + [action])
                        } label: {
                            Label(action.settingsTitle, systemImage: action.symbolName)
                        }
                    }
                } header: {
                    Text("Available Actions")
                } footer: {
                    Text("Actions not selected for direct display remain available under More when they are relevant to the current article scope.")
                }
            }

            Section {
                Button("Reset to Default") {
                    preferences.resetToDefault()
                }
            }
        }
        .navigationTitle("Action Bar")
        .toolbar { EditButton() }
    }
}