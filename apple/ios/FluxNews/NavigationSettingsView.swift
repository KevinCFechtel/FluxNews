import SwiftUI

struct NavigationSettingsView: View {
    var store: NewsreaderStore

    var body: some View {
        Form {
            Toggle("Hide empty feeds", isOn: Binding(get: { store.hideEmptyNavigationEntries }, set: store.setHideEmptyNavigationEntries))
            Picker("Startup scope", selection: Binding(get: { store.startupScope }, set: store.setStartupScope)) {
                Text("All News").tag(StartupScopePreference.allNews)
                Text("Starred").tag(StartupScopePreference.starred)
                Text("Category").tag(StartupScopePreference.category)
                Text("Feed").tag(StartupScopePreference.feed)
            }
            if store.startupScope == .category {
                Picker("Startup category", selection: Binding(get: { store.startupCategoryID ?? 0 }, set: { store.setStartupCategoryID($0) })) {
                    ForEach(store.catalog.categories, id: \.id) { Text($0.title).tag($0.id) }
                }
            }
            if store.startupScope == .feed {
                Picker("Startup feed", selection: Binding(get: { store.startupFeedID ?? 0 }, set: { store.setStartupFeedID($0) })) {
                    ForEach(store.catalog.feeds, id: \.id) { Text($0.title).tag($0.id) }
                }
            }
        }
        .navigationTitle("Navigation")
    }
}
