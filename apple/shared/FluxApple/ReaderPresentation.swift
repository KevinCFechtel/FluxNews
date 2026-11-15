import Foundation
import SwiftUI

enum ReaderPresentationKind: Equatable { case sheet, inspector }

enum AdaptivePresentation: Equatable {
    case compact
    case regular

    var usesPersistentSplitNavigation: Bool {
        self == .regular
    }

    var readerPresentationKind: ReaderPresentationKind {
        self == .regular ? .inspector : .sheet
    }
}

enum AdaptivePresentationPolicy {
    /// Persistent split navigation belongs to a tablet-sized canvas, not to a
    /// phone turned sideways.
    ///
    /// A phone in landscape reports regular *width* but compact *height*; an
    /// iPad reports regular for both, and so does a foldable that is open.
    /// Deciding on both classes therefore separates "wide enough" from "wide
    /// because it is lying down" — and covers every form factor, including a
    /// folding phone in either state, without naming a single device.
    static func presentation(
        horizontalSizeClass: UserInterfaceSizeClass?,
        verticalSizeClass: UserInterfaceSizeClass?
    ) -> AdaptivePresentation {
        horizontalSizeClass == .regular && verticalSizeClass == .regular ? .regular : .compact
    }
}

enum AdaptiveShellTransitionPolicy {
    static func navigationSheetPresented(after presentation: AdaptivePresentation, wasPresented: Bool) -> Bool {
        presentation.usesPersistentSplitNavigation ? false : wasPresented
    }

    static func splitColumnVisibility(after presentation: AdaptivePresentation) -> NavigationSplitViewVisibility {
        presentation.usesPersistentSplitNavigation ? .automatic : .detailOnly
    }

    static func constrainedSplitColumnVisibility(
        requested: NavigationSplitViewVisibility,
        presentation: AdaptivePresentation
    ) -> NavigationSplitViewVisibility {
        presentation.usesPersistentSplitNavigation ? requested : .detailOnly
    }
}

enum ReaderDocumentNotice {
    static func text(simplified: Bool, truncated: Bool) -> String? {
        switch (simplified, truncated) {
        case (true, true): String(localized: "Some content was simplified and truncated")
        case (true, false): String(localized: "Some content was simplified")
        case (false, true): String(localized: "Some content was truncated")
        case (false, false): nil
        }
    }
}

struct ReaderArticleHeader: View {
    private static let dateFormatter = ISO8601DateFormatter()
    let article: ArticleSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(article.feedTitle).font(.subheadline).foregroundStyle(.secondary)
            Text(article.title).font(.title2.bold()).textSelection(.enabled)
            if let date = Self.dateFormatter.date(from: article.publishedAt) {
                Text(date.formatted(date: .long, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 680, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct ReaderDocumentContent: View {
    let document: ReaderDocument
    let openOriginal: (() -> Void)?
    let contentPadding: CGFloat

    init(
        document: ReaderDocument,
        openOriginal: (() -> Void)?,
        contentPadding: CGFloat = 24
    ) {
        self.document = document
        self.openOriginal = openOriginal
        self.contentPadding = contentPadding
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ReaderBlocksView(blocks: document.blocks)
            if let notice = ReaderDocumentNotice.text(
                simplified: document.hasSimplifiedContent,
                truncated: document.wasTruncated
            ) {
                HStack(spacing: 4) {
                    Text(notice)
                    if let openOriginal {
                        Text("·").foregroundStyle(.tertiary)
                        Button("Open Original", action: openOriginal)
                            .buttonStyle(.borderless)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: 680, alignment: .leading)
        .padding(contentPadding)
        .frame(maxWidth: .infinity, alignment: .center)
    }

}

private struct ReaderBlocksView: View {
    let blocks: [ReaderBlock]

    var body: some View {
        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in blockView(block) }
    }

    @ViewBuilder
    private func blockView(_ block: ReaderBlock) -> some View {
        switch block {
        case let .paragraph(inlines):
            Text(readerText(inlines)).font(.body).fixedSize(horizontal: false, vertical: true)
        case let .heading(level, inlines):
            Text(readerText(inlines)).font(level <= 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline).fixedSize(horizontal: false, vertical: true)
        case let .image(url, alt, link):
            ReaderImage(url: url, alt: alt, link: link)
        case let .listBlock(ordered, items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text(ordered ? "\(index + 1)." : "•").foregroundStyle(.secondary)
                        ReaderBlocksView(blocks: item.blocks)
                    }
                }
            }
            .padding(.leading, 12)
        case let .quote(blocks):
            ReaderBlocksView(blocks: blocks)
                .padding(.leading, 16)
                .overlay(alignment: .leading) { Rectangle().fill(.secondary.opacity(0.45)).frame(width: 3) }
                .foregroundStyle(.secondary)
        case let .codeBlock(text):
            Text(text)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        case .horizontalRule:
            Divider().padding(.vertical, 4)
        case let .externalContent(url, label):
            if let url = URL(string: url) { Link(label ?? url.absoluteString, destination: url).lineLimit(2) }
        }
    }

    private func readerText(_ inlines: [ReaderInline]) -> AttributedString {
        inlines.reduce(into: AttributedString()) { result, inline in
            switch inline {
            case let .text(text): result += AttributedString(text)
            case let .bold(inlines):
                var text = readerText(inlines); text.inlinePresentationIntent = .stronglyEmphasized; result += text
            case let .italic(inlines):
                var text = readerText(inlines); text.inlinePresentationIntent = .emphasized; result += text
            case let .code(text):
                var text = AttributedString(text); text.font = .system(.body, design: .monospaced); result += text
            case let .link(url, inlines):
                var text = readerText(inlines); text.link = URL(string: url); result += text
            }
        }
    }
}

private struct ReaderImage: View {
    let url: String
    let alt: String?
    let link: String?

    var body: some View {
        Group {
            if let link, let destination = URL(string: link) {
                Link(destination: destination) { imageContent }
            } else {
                imageContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(alt ?? String(localized: "Article image"))
    }

    @ViewBuilder
    private var imageContent: some View {
        if let imageURL = URL(string: url) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case let .success(image): image.resizable().scaledToFit()
                case .failure: fallback
                default: ProgressView().frame(height: 120)
                }
            }
        } else {
            fallback
        }
    }

    @ViewBuilder
    private var fallback: some View {
        if let link, let destination = URL(string: link) {
            Link(alt?.isEmpty == false ? alt! : String(localized: "Open image"), destination: destination)
                .padding(12)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
