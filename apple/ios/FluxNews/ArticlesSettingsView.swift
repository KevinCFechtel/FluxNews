import SwiftUI

struct ArticlesSettingsView: View {
    var store: NewsreaderStore
    @ObservedObject var bootstrapper: CoreBootstrapper

    @State private var liveMutationDeliveryEnabled = true
    @State private var mutationDeliveryLoaded = false
    @State private var mutationDeliverySaving = false
    @State private var mutationDeliveryError: String?

    @State private var retention: ReadArticleRetention = .days90
    @State private var retentionLoaded = false
    @State private var retentionSaving = false
    @State private var retentionError: String?

    @State private var detailCharacterLimit: UInt32 = 10_000
    @State private var detailCharacterLimitLoaded = false
    @State private var detailCharacterLimitSaving = false
    @State private var detailCharacterLimitError: String?

    var body: some View {
        Form {
            Picker("Open article", selection: Binding(get: { store.clickOnNews }, set: store.setClickOnNews)) {
                Text("Original link").tag(ClickOnNews.openLink)
                Text("Reader").tag(ClickOnNews.openDetailView)
            }
            Picker("Presentation", selection: Binding(get: { store.articlePresentationMode }, set: store.setArticlePresentationMode)) {
                ForEach(ArticlePresentationMode.allCases, id: \.self) { Text(String(localized: String.LocalizationValue($0.displayNameKey))).tag($0) }
            }
            Picker("Preview lines", selection: Binding(get: { store.articlePreviewLines }, set: store.setArticlePreviewLines)) {
                ForEach(ArticlePreviewLines.allCases, id: \.self) { Text(String(format: String(localized: "%lld lines"), $0.rawValue)).tag($0) }
            }
            Toggle("Show article count", isOn: Binding(get: { store.showArticleCount }, set: store.setShowArticleCount))
            Toggle("Show relative publication time", isOn: Binding(get: { store.showRelativePublicationTime }, set: store.setShowRelativePublicationTime))
            Toggle("Remove articles when read", isOn: Binding(get: { store.removeArticlesWhenMarkedRead }, set: store.setRemoveArticlesWhenMarkedRead))
            Toggle("Mark read on scrollover", isOn: Binding(get: { store.markReadOnScrolloverEnabled }, set: store.setMarkReadOnScrolloverEnabled))

            Section {
                Picker(
                    "Keep read articles",
                    selection: Binding(
                        get: { retention },
                        set: { newValue in
                            guard retentionLoaded, !retentionSaving else { return }
                            let previous = retention
                            retention = newValue
                            retentionSaving = true
                            retentionError = nil
                            Task {
                                let result = await bootstrapper
                                    .setReadArticleRetentionPreference(newValue)
                                switch result {
                                case .success:
                                    break
                                case .failure:
                                    retention = previous
                                    retentionError = String(
                                        localized: "Read article retention setting could not be saved. Please try again."
                                    )
                                }
                                retentionSaving = false
                            }
                        }
                    )
                ) {
                    Text("30 days").tag(ReadArticleRetention.days30)
                    Text("60 days").tag(ReadArticleRetention.days60)
                    Text("90 days").tag(ReadArticleRetention.days90)
                    Text("180 days").tag(ReadArticleRetention.days180)
                    Text("365 days").tag(ReadArticleRetention.days365)
                }
                .disabled(!retentionLoaded || retentionSaving)

                Picker(
                    "Reader detail limit",
                    selection: Binding(
                        get: { detailCharacterLimit },
                        set: { newValue in
                            guard detailCharacterLimitLoaded,
                                  !detailCharacterLimitSaving
                            else { return }
                            let previous = detailCharacterLimit
                            detailCharacterLimit = newValue
                            detailCharacterLimitSaving = true
                            detailCharacterLimitError = nil
                            Task {
                                let result = await bootstrapper
                                    .setDetailCharacterLimitPreference(newValue)
                                switch result {
                                case .success:
                                    break
                                case .failure:
                                    detailCharacterLimit = previous
                                    detailCharacterLimitError = String(
                                        localized: "Reader detail limit setting could not be saved. Please try again."
                                    )
                                }
                                detailCharacterLimitSaving = false
                            }
                        }
                    )
                ) {
                    Text("5,000 characters").tag(UInt32(5_000))
                    Text("10,000 characters").tag(UInt32(10_000))
                    Text("20,000 characters").tag(UInt32(20_000))
                }
                .disabled(
                    !detailCharacterLimitLoaded
                        || detailCharacterLimitSaving
                )
            } header: {
                Text("Storage & Reader")
            } footer: {
                Text("Read article retention controls how long synchronized read items remain in local history. The Reader detail limit controls how much article text the Core keeps when a feed uses truncated Reader content.")
            }

            if retentionSaving || detailCharacterLimitSaving {
                Section {
                    HStack {
                        ProgressView()
                        Text("Saving…")
                    }
                }
            }

            if let retentionError {
                Section {
                    Text(retentionError)
                        .foregroundStyle(.red)
                }
            }

            if let detailCharacterLimitError {
                Section {
                    Text(detailCharacterLimitError)
                        .foregroundStyle(.red)
                }
            }

            Section {
                swipeSideSettings(
                    title: String(localized: "Leading Side"),
                    side: .leading
                )
                swipeSideSettings(
                    title: String(localized: "Trailing Side"),
                    side: .trailing
                )
            } header: {
                Text("Swipe Actions")
            } footer: {
                Text("Each side supports up to two actions. The Full Swipe action is the outer action and runs when you deliberately swipe through the row.")
            }

            Section {
                Toggle(
                    "Sync article changes immediately",
                    isOn: Binding(
                        get: { liveMutationDeliveryEnabled },
                        set: { newValue in
                            guard mutationDeliveryLoaded, !mutationDeliverySaving else { return }
                            let previous = liveMutationDeliveryEnabled
                            liveMutationDeliveryEnabled = newValue
                            mutationDeliverySaving = true
                            mutationDeliveryError = nil
                            Task {
                                let result = await bootstrapper.setMutationDeliveryPreference(newValue)
                                switch result {
                                case .success:
                                    break
                                case .failure:
                                    liveMutationDeliveryEnabled = previous
                                    mutationDeliveryError = String(
                                        localized: "Immediate article sync setting could not be saved. Please try again."
                                    )
                                }
                                mutationDeliverySaving = false
                            }
                        }
                    )
                )
                .disabled(!mutationDeliveryLoaded || mutationDeliverySaving)
            } footer: {
                Text("When enabled, read/unread and star changes are saved locally first and then sent to Miniflux immediately. If delivery fails, FluxNews keeps the change pending for a later retry.")
            }

            if mutationDeliverySaving {
                Section {
                    HStack {
                        ProgressView()
                        Text("Saving…")
                    }
                }
            }

            if let mutationDeliveryError {
                Section {
                    Text(mutationDeliveryError)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Articles")
        .task {
            if !retentionLoaded {
                let result = await bootstrapper.readArticleRetentionPreference()
                switch result {
                case let .success(value):
                    retention = value
                    retentionLoaded = true
                case .failure:
                    retentionError = String(
                        localized: "Read article retention setting could not be loaded. Please try again."
                    )
                }
            }

            if !detailCharacterLimitLoaded {
                let result = await bootstrapper.detailCharacterLimitPreference()
                switch result {
                case let .success(value):
                    detailCharacterLimit = value
                    detailCharacterLimitLoaded = true
                case .failure:
                    detailCharacterLimitError = String(
                        localized: "Reader detail limit setting could not be loaded. Please try again."
                    )
                }
            }

            if !mutationDeliveryLoaded {
                let result = await bootstrapper.mutationDeliveryPreference()
                switch result {
                case let .success(enabled):
                    liveMutationDeliveryEnabled = enabled
                    mutationDeliveryLoaded = true
                case .failure:
                    mutationDeliveryError = String(
                        localized: "Immediate article sync setting could not be loaded. Please try again."
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func swipeSideSettings(
        title: String,
        side: IOSArticleSwipeSide
    ) -> some View {
        let configuration = store.articleSwipeConfiguration
        let fullSwipe = configuration.fullSwipeAction(for: side)
        let additional = configuration.additionalAction(for: side)

        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Picker(
                "Full Swipe",
                selection: Binding<IOSArticleSwipeAction?>(
                    get: {
                        store.articleSwipeConfiguration.fullSwipeAction(for: side)
                    },
                    set: { store.setArticleSwipeAction($0, side: side, slot: .fullSwipe) }
                )
            ) {
                Text("None").tag(IOSArticleSwipeAction?.none)
                ForEach(IOSArticleSwipeAction.allCases, id: \.self) { action in
                    Text(action.title).tag(Optional(action))
                }
            }

            Picker(
                "Additional Action",
                selection: Binding<IOSArticleSwipeAction?>(
                    get: {
                        store.articleSwipeConfiguration.additionalAction(for: side)
                    },
                    set: { store.setArticleSwipeAction($0, side: side, slot: .additional) }
                )
            ) {
                Text("None").tag(IOSArticleSwipeAction?.none)
                ForEach(IOSArticleSwipeAction.allCases, id: \.self) { action in
                    Text(action.title).tag(Optional(action))
                }
            }
            .disabled(fullSwipe == nil)

            if let fullSwipe {
                Text(
                    additional == nil
                        ? String(
                            format: String(localized: "Full Swipe: %@"),
                            fullSwipe.title
                        )
                        : String(
                            format: String(localized: "Inner: %@ · Full Swipe: %@"),
                            additional?.title ?? "",
                            fullSwipe.title
                        )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
