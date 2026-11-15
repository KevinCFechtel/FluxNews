import SwiftUI

struct DeveloperDiagnosticsView: View {
    @ObservedObject var bootstrapper: CoreBootstrapper
    @State private var legacyResult = LegacyStateDiscovery.probe()
    @State private var imageCacheDiagnostics: ArticleImageCacheDiagnosticsSnapshot?
    @State private var imagePresentationDiagnostics: ArticleImagePresentationDiagnosticsSnapshot?

    var body: some View {
        NavigationStack {
            Form {
                Section("Rust Core") {
                    LabeledContent("Status", value: bootstrapper.state.title)
                    if case let .ready(health) = bootstrapper.state { LabeledContent("Smoke test", value: health) }
                    if case let .recoverableError(message) = bootstrapper.state { Text(message).foregroundStyle(.red) }
                }
                Section("Sandbox paths") { Text(bootstrapper.pathsDescription).font(.footnote.monospaced()).textSelection(.enabled) }
                Section("Legacy migration feasibility") {
                    ForEach(LegacyStateDiscovery.redactedSummary(legacyResult).sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        LabeledContent(localizedDiagnosticLabel(key), value: value)
                    }
                    Text("Read-only discovery; no legacy data is imported or modified.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Article Image Presentation") {
                    if let imagePresentationDiagnostics {
                        LabeledContent("Queued ready images", value: "\(imagePresentationDiagnostics.queued)")
                        LabeledContent("Maximum ready queue", value: "\(imagePresentationDiagnostics.maximumQueued)")
                        LabeledContent("Presented images", value: "\(imagePresentationDiagnostics.presented)")
                        LabeledContent("Discarded stale images", value: "\(imagePresentationDiagnostics.discarded)")
                        LabeledContent("Average ready→presented", value: imagePresentationDiagnostics.averageDelayText)
                        LabeledContent("Maximum ready→presented", value: imagePresentationDiagnostics.maximumDelayText)
                    } else {
                        ProgressView()
                    }

                    Button("Refresh Image Presentation Metrics") {
                        refreshImagePresentationDiagnostics()
                    }
                    Button("Reset Image Presentation Metrics") {
                        IOSArticleImagePresentationScheduler.shared.resetMetrics()
                        refreshImagePresentationDiagnostics()
                    }

                    Text("During scrolling, at most one newly finished async article image is presented per display frame. Cache hits remain immediate.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Article Image Cache") {
                    if let imageCacheDiagnostics {
                        LabeledContent("Visible hits", value: "\(imageCacheDiagnostics.visibleHits)")
                        LabeledContent("Visible misses", value: "\(imageCacheDiagnostics.visibleMisses)")
                        LabeledContent("Visible hit rate", value: imageCacheDiagnostics.visibleHitRateText)
                        LabeledContent("Cache insertions", value: "\(imageCacheDiagnostics.insertions)")
                        LabeledContent("Cache evictions", value: "\(imageCacheDiagnostics.evictions)")
                        LabeledContent("Active image jobs", value: "\(imageCacheDiagnostics.activeOperations)")
                        LabeledContent("Started image jobs", value: "\(imageCacheDiagnostics.startedOperations)")
                        LabeledContent("Retired image jobs", value: "\(imageCacheDiagnostics.retiredOperations)")
                    } else {
                        ProgressView()
                    }

                    Button("Refresh Image Cache Metrics") {
                        Task { await refreshImageCacheDiagnostics() }
                    }
                    Button("Reset Image Cache Metrics") {
                        Task {
                            await ArticleImagePipeline.shared.resetMetrics()
                            await refreshImageCacheDiagnostics()
                        }
                    }

                    Text("For the warm-cache scroll test: scroll a short section once, jump back to the top, reset these metrics, then scroll the same section again. A warm second pass should produce mostly visible hits and very few visible misses.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

#if DEBUG || FLUX_PERFORMANCE_DIAGNOSTICS
                Section("Timeline Performance") {
                    Button("Reset Timeline Metrics") {
                        Task {
                            await IOSUIKitTimelinePerformanceDiagnostics.resetAndPrint()
                            await refreshImageCacheDiagnostics()
                        }
                    }
                    Button("Print Timeline Metrics") {
                        Task { await IOSUIKitTimelinePerformanceDiagnostics.printSnapshot() }
                    }
                }
#endif
            }
            .navigationTitle("Developer Diagnostics")
            .task {
                await refreshImageCacheDiagnostics()
                refreshImagePresentationDiagnostics()
            }
        }
    }

    private func refreshImageCacheDiagnostics() async {
        imageCacheDiagnostics = ArticleImageCacheDiagnosticsSnapshot(
            metrics: await ArticleImagePipeline.shared.metrics()
        )
    }

    private func refreshImagePresentationDiagnostics() {
        imagePresentationDiagnostics = ArticleImagePresentationDiagnosticsSnapshot(
            metrics: IOSArticleImagePresentationScheduler.shared.metrics()
        )
    }

    private func localizedDiagnosticLabel(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }
}


struct ArticleImageCacheDiagnosticsSnapshot: Equatable {
    let visibleHits: Int
    let visibleMisses: Int
    let insertions: Int
    let evictions: Int
    let activeOperations: Int
    let startedOperations: Int
    let retiredOperations: Int

    init(metrics: ArticleImagePipeline.Metrics) {
        visibleHits = metrics.visibleMemoryCacheHits
        visibleMisses = metrics.visibleMemoryCacheMisses
        insertions = metrics.memoryCacheInsertions
        evictions = metrics.memoryCacheEvictions
        activeOperations = metrics.activeOperations
        startedOperations = metrics.startedOperations
        retiredOperations = metrics.retiredOperations
    }

    var visibleHitRate: Double? {
        let total = visibleHits + visibleMisses
        guard total > 0 else { return nil }
        return Double(visibleHits) / Double(total)
    }

    var visibleHitRateText: String {
        guard let visibleHitRate else { return "n/a" }
        return String(format: "%.1f%%", visibleHitRate * 100)
    }
}


struct ArticleImagePresentationDiagnosticsSnapshot: Equatable {
    let queued: Int
    let maximumQueued: Int
    let presented: Int
    let discarded: Int
    let averageDelayMilliseconds: Double
    let maximumDelayMilliseconds: Double

    init(metrics: IOSArticleImagePresentationScheduler.Metrics) {
        queued = metrics.queued
        maximumQueued = metrics.maximumQueued
        presented = metrics.presented
        discarded = metrics.discarded
        averageDelayMilliseconds = metrics.averageDelayMilliseconds
        maximumDelayMilliseconds = metrics.maximumDelayMilliseconds
    }

    var averageDelayText: String { String(format: "%.1f ms", averageDelayMilliseconds) }
    var maximumDelayText: String { String(format: "%.1f ms", maximumDelayMilliseconds) }
}
