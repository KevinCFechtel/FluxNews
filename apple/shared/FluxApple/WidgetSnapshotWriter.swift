import Foundation
import OSLog

enum WidgetSnapshotWriter {
    static func refresh(core: Flux, store: WidgetSnapshotStore) throws {
        let data: WidgetData
        do {
            data = try core.widgetData()
        } catch {
            WidgetSnapshotDiagnostics.logger.error(
                "Widget data could not be read from Flux core error=\(error.localizedDescription, privacy: .public)"
            )
            throw error
        }

        var iconReferences: [Int64: (normal: String?, dark: String?)] = [:]
        for feedID in Set(data.articles.map(\.feedId)) {
            let normal = writeIcon(core: core, store: store, feedID: feedID, variant: .normal)
            let dark = writeIcon(core: core, store: store, feedID: feedID, variant: .dark)
            iconReferences[feedID] = (normal, dark)
        }

        let snapshot = WidgetSnapshotV1(
            schemaVersion: WidgetSnapshotV1.schemaVersion,
            state: data.lastSuccessfulSyncAt == nil ? .awaitingSuccessfulSync : .ready,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            lastSuccessfulSyncAt: data.lastSuccessfulSyncAt,
            feeds: data.feeds.map {
                .init(
                    id: $0.id,
                    categoryID: $0.categoryId,
                    title: $0.title,
                    normalIconFile: iconReferences[$0.id]?.normal,
                    darkIconFile: iconReferences[$0.id]?.dark
                )
            },
            categories: data.categories.map {
                .init(id: $0.id, title: $0.title)
            },
            articles: data.articles.map {
                .init(
                    id: $0.id,
                    feedID: $0.feedId,
                    categoryID: $0.categoryId,
                    feedTitle: $0.feedTitle,
                    title: $0.title,
                    publishedAt: $0.publishedAt,
                    isRead: $0.isRead,
                    isStarred: $0.isStarred
                )
            },
            counts: .init(
                allUnread: data.counts.allUnread,
                bookmarks: data.counts.bookmarks,
                feedUnread: data.counts.feedUnread.map {
                    .init(id: $0.id, count: $0.count)
                },
                categoryUnread: data.counts.categoryUnread.map {
                    .init(id: $0.id, count: $0.count)
                }
            ),
            configuration: .init(
                allArticles: data.counts.allArticles,
                bookmarksUnread: data.counts.bookmarksUnread,
                feedAll: data.counts.feedAll.map {
                    .init(id: $0.id, count: $0.count)
                },
                categoryAll: data.counts.categoryAll.map {
                    .init(id: $0.id, count: $0.count)
                }
            )
        )

        do {
            try store.write(snapshot)
        } catch {
            WidgetSnapshotDiagnostics.logger.error(
                "Widget snapshot could not be written path=\(store.snapshotPath, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    private static func writeIcon(
        core: Flux,
        store: WidgetSnapshotStore,
        feedID: Int64,
        variant: FeedIconVariant
    ) -> String? {
        do {
            guard let icon = try core.feedIcon(feedId: feedID, variant: variant) else {
                return nil
            }
            return try store.writeIcon(
                Data(icon.pngData),
                feedID: feedID,
                dark: variant == .dark
            )
        } catch {
            WidgetSnapshotDiagnostics.logger.warning(
                "Widget feed icon unavailable feed_id=\(feedID, privacy: .public) variant=\(variant == .dark ? "dark" : "normal", privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }
}
