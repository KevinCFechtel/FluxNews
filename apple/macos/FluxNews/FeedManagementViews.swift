import SwiftUI

struct AddFeedView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: BrowserStore
    @State private var form = AddFeedForm()
    @State private var candidates: [DiscoveredSubscription] = []
    @State private var selectedCandidateIndex: Int?
    @State private var isDiscovering = false
    @State private var isCreating = false
    @State private var message: String?
    @State private var advancedVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if candidates.isEmpty {
                formContent
            } else {
                candidateContent
            }
            if let message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            Divider()
            HStack {
                if !candidates.isEmpty {
                    Button("Back") { candidates = []; selectedCandidateIndex = nil; message = nil }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                if candidates.isEmpty {
                    Button { discover() } label: {
                        if isDiscovering { Text("Discovering...") } else { Text("Continue") }
                    }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isDiscovering || isCreating || form.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button { createSelectedCandidate() } label: {
                        if isCreating { Text("Adding...") } else { Text("Add Feed") }
                    }
                        .keyboardShortcut(.defaultAction)
                        .disabled(selectedCandidateIndex == nil || isCreating)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Feed").font(.title2.bold())
            Text("Enter a website or feed URL. Flux asks Miniflux to discover available subscriptions.")
                .font(.callout)
                .foregroundStyle(.secondary)
            LabeledContent("URL") { TextField("https://example.com", text: $form.url) }
            LabeledContent("Category") {
                Picker("Category", selection: $form.categoryID) {
                    Text("Use Miniflux default").tag(nil as Int64?)
                    ForEach(store.catalog.categories, id: \.id) { category in
                        Text(category.title).tag(Optional(category.id))
                    }
                }
                .labelsHidden()
            }
            DisclosureGroup("Advanced", isExpanded: $advancedVisible) {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Username") { TextField("Optional", text: $form.username) }
                    LabeledContent("Password") { SecureField("Optional", text: $form.password) }
                    LabeledContent("User Agent") { TextField("Optional", text: $form.userAgent) }
                    optionalBooleanPicker("Crawler", selection: $form.crawler)
                    LabeledContent("Scraper Rules") { TextField("Optional", text: $form.scraperRules, axis: .vertical).lineLimit(2...4) }
                    LabeledContent("Rewrite Rules") { TextField("Optional", text: $form.rewriteRules, axis: .vertical).lineLimit(2...4) }
                    LabeledContent("Blocklist Rules") { TextField("Optional", text: $form.blocklistRules, axis: .vertical).lineLimit(2...4) }
                    LabeledContent("Keeplist Rules") { TextField("Optional", text: $form.keeplistRules, axis: .vertical).lineLimit(2...4) }
                    optionalBooleanPicker("Disabled", selection: $form.disabled)
                    optionalBooleanPicker("Ignore HTTP Cache", selection: $form.ignoreHttpCache)
                    optionalBooleanPicker("Fetch Via Proxy", selection: $form.fetchViaProxy)
                }
                .padding(.top, 10)
            }
        }
    }

    private var candidateContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a Feed").font(.title2.bold())
            Text("Miniflux found multiple subscriptions for this URL.")
                .font(.callout)
                .foregroundStyle(.secondary)
            List(candidates.indices, id: \.self, selection: $selectedCandidateIndex) { index in
                let candidate = candidates[index]
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.title.isEmpty ? candidate.url : candidate.title).fontWeight(.medium)
                    Text(candidate.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if !candidate.feedType.isEmpty { Text(candidate.feedType.uppercased()).font(.caption2).foregroundStyle(.tertiary) }
                }
                .tag(Optional(index))
            }
            .frame(height: 220)
        }
    }

    private func optionalBooleanPicker(_ title: String, selection: Binding<AddFeedOptionalBoolean>) -> some View {
        LabeledContent(title) {
            Picker(title, selection: selection) {
                ForEach(AddFeedOptionalBoolean.allCases) { value in Text(value.title).tag(value) }
            }
            .labelsHidden()
        }
    }

    private func discover() {
        message = nil
        isDiscovering = true
        store.discoverSubscriptions(form.discoveryRequest()) { result in
            isDiscovering = false
            switch result {
            case let .success(subscriptions):
                switch AddFeedDiscoveryOutcome.from(subscriptions) {
                case .none:
                    showError("Miniflux did not find a subscription for this URL.")
                case let .automatic(subscription):
                    create(feedURL: subscription.url)
                case .choose:
                    candidates = subscriptions
                }
            case .failure:
                showError(String(localized: "Could not discover feeds. Please try again."))
            }
        }
    }

    private func createSelectedCandidate() {
        guard let selectedCandidateIndex else { return }
        create(feedURL: candidates[selectedCandidateIndex].url)
    }

    private func create(feedURL: String) {
        message = nil
        isCreating = true
        store.createFeed(form.createRequest(feedURL: feedURL)) { result in
            isCreating = false
            switch result {
            case .success:
                store.showActionConfirmation("Feed added. It will appear after the next refresh.")
                dismiss()
            case .failure:
                showError(String(localized: "Could not add feed. Please try again."))
            }
        }
    }

    private func showError(_ message: String) {
        self.message = message
        store.errorMessage = message
    }
}

struct AddCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: BrowserStore
    @State private var title = ""
    @State private var isCreating = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Category").font(.title2.bold())
            LabeledContent("Name") { TextField("Category name", text: $title) }
            if let message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button { create() } label: {
                    if isCreating { Text("Adding...") } else { Text("Add") }
                }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isCreating || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func create() {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        message = nil
        isCreating = true
        store.createCategory(title) { result in
            isCreating = false
            switch result {
            case .success:
                store.showActionConfirmation("Category added. It will appear after the next refresh.")
                dismiss()
            case .failure:
                let message = String(localized: "Could not add category. Please try again.")
                self.message = message
                store.errorMessage = message
            }
        }
    }
}
