import SwiftUI

enum IOSActionFeedbackKind: CaseIterable, Equatable {
    case linkCopied
    case savedToService
    case noThirdPartyIntegration
    case addedToListeningList
    case removedFromListeningList
    case downloadRequested
    case downloadCancelled
    case downloadDeletionRequested

    var message: String {
        switch self {
        case .linkCopied:
            String(localized: "Link copied")
        case .savedToService:
            String(localized: "Saved to third-party service")
        case .noThirdPartyIntegration:
            String(localized: "No third-party integration is configured in Miniflux")
        case .addedToListeningList:
            String(localized: "Added to Listening List")
        case .removedFromListeningList:
            String(localized: "Removed from Listening List")
        case .downloadRequested:
            String(localized: "Download requested")
        case .downloadCancelled:
            String(localized: "Download cancelled")
        case .downloadDeletionRequested:
            String(localized: "Download deletion requested")
        }
    }

    var symbolName: String {
        switch self {
        case .linkCopied:
            "doc.on.doc"
        case .savedToService:
            "checkmark.circle.fill"
        case .noThirdPartyIntegration:
            "info.circle"
        case .addedToListeningList:
            "headphones"
        case .removedFromListeningList:
            "minus.circle"
        case .downloadRequested:
            "arrow.down.circle"
        case .downloadCancelled:
            "xmark.circle"
        case .downloadDeletionRequested:
            "trash"
        }
    }
}

struct IOSActionFeedbackItem: Equatable, Identifiable {
    let id: UInt64
    let kind: IOSActionFeedbackKind
}

enum IOSActionFeedbackPresentation {
    static let autoDismissDelay: Duration = .seconds(3)
    static let baseBottomPadding: CGFloat = 18
    static let bottomActionBarClearance: CGFloat = 54
    static let miniPlayerClearance: CGFloat = 58

    static func bottomPadding(
        hasBottomActionBar: Bool,
        hasMiniPlayer: Bool = false
    ) -> CGFloat {
        baseBottomPadding
            + (hasBottomActionBar ? bottomActionBarClearance : 0)
            + (hasMiniPlayer ? miniPlayerClearance : 0)
    }

    static func shouldDismiss(
        current: IOSActionFeedbackItem?,
        id: UInt64
    ) -> Bool {
        current?.id == id
    }
}

struct IOSActionFeedbackBanner: View {
    let item: IOSActionFeedbackItem

    var body: some View {
        Label {
            Text(item.kind.message)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: item.kind.symbolName)
                .foregroundStyle(Color.accentColor)
        }
        .font(.callout.weight(.semibold))
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background {
            ArticleListChromeCapsuleBackground(
                usesSystemToolbarGlass: false,
                isInteractive: false
            )
        }
        .overlay {
            Capsule()
                .stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
        }
        .shadow(radius: 5, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.kind.message)
        .allowsHitTesting(false)
    }
}
