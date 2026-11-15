import SwiftUI

struct SearchResultsView: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var transferState: MediaTransferPresentationState
    let onPlay: (Enclosure) -> Void
    let onDownload: (Enclosure) -> Void
    let onDelete: (Enclosure) -> Void
    let onAdd: (Int64) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Search Miniflux", text: $store.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { store.submitSearch() }
                if !store.searchQuery.isEmpty {
                    Button { store.clearSearch() } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(12)

            if let error = store.errorMessage {
                ContentUnavailableView("Search failed", systemImage: "exclamationmark.triangle", description: Text(error))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.isSearching && store.articles.isEmpty {
                ProgressView("Searching Miniflux...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !store.hasSearched {
                ContentUnavailableView("Search Miniflux", systemImage: "magnifyingglass", description: Text("Enter a query and press Return."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.articles.isEmpty {
                ContentUnavailableView("No results", systemImage: "magnifyingglass", description: Text("No Miniflux entries matched your search."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    Text("\(store.searchTotal) results").font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.bottom, 6)
                    ScrollView {
                        LazyVStack(spacing: store.articlePresentationMode == .visual ? 4 : 0) {
                            ForEach(store.articles, id: \.id) { article in
                                ArticleItem(article: article, mode: store.articlePresentationMode, selected: false, audioState: store.articleAudioActionStates[article.id], transferState: transferState, store: store, onSelect: {}, onPlayAudio: onPlay, onDownloadAudio: onDownload, onDeleteDownload: onDelete, onAddToListeningList: { onAdd(article.id) }, onHoverChanged: { _ in })
                                    .onAppear { if article.id == store.articles.last?.id { store.loadMoreSearchResults() } }
                                if store.articlePresentationMode == .compact {
                                    Divider().padding(.leading, 12)
                                }
                            }
                            if store.isSearching { ProgressView().padding() }
                        }
                    }
                }
            }
        }
    }
}
