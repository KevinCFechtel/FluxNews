import UIKit

@MainActor
final class IOSUIKitArticleCell: UITableViewCell {
    static func reuseIdentifier(for variant: IOSUIKitArticleCellLayoutVariant) -> String {
        switch variant {
        case .compact: return "IOSUIKitArticleCell.compact"
        case .visualTextOnly: return "IOSUIKitArticleCell.visualTextOnly"
        case .visualPortrait: return "IOSUIKitArticleCell.visualPortrait"
        case .visualLandscape: return "IOSUIKitArticleCell.visualLandscape"
        case .visualSideTitle: return "IOSUIKitArticleCell.visualSideTitle"
        case .visualSideTitleWide: return "IOSUIKitArticleCell.visualSideTitleWide"
        case .visualSideTitleTextOnly: return "IOSUIKitArticleCell.visualSideTitleTextOnly"
        }
    }

    // A plain container, not a `UIStackView`. Setting `isHidden` on an
    // arranged subview makes the stack add and remove constraints, and
    // `previewLabel.isHidden` is set on every `configure`.
    private let textContainer = UIView()
    private let titleLabel = UILabel()
    private let starImageView = UIImageView(image: UIImage(systemName: "star.fill"))
    private let metadataRow = UIView()
    private let unreadIndicator = UIView()
    private let feedIconContainer = UIView()
    private let feedIconImageView = UIImageView()
    private let feedIconFallbackLabel = UILabel()
    private let feedTitleLabel = UILabel()
    private let audioContainer = UIView()
    private let audioImageView = UIImageView(image: UIImage(systemName: "headphones"))
    private let publicationTimeIconView = UIImageView(image: UIImage(systemName: "clock.arrow.circlepath"))
    private let dateLabel = UILabel()
    private let landscapeReadingTimeContainer = UIView()
    private let landscapeReadingTimeIconView = UIImageView(image: UIImage(systemName: "doc.text"))
    private let landscapeReadingTimeLabel = UILabel()
    private let commentsContainer = UIView()
    private let commentsImageView = UIImageView(image: UIImage(systemName: "bubble.left"))
    private let previewLabel = UILabel()
    private let previewContinuationLabel = UILabel()
    private var sidePreviewHeightConstraint: NSLayoutConstraint!
    private var sideContinuationHeightConstraint: NSLayoutConstraint!
    private var sideContinuationTopConstraint: NSLayoutConstraint!
    private let articleImageView = UIImageView()
    private let imagePlaceholder = UIImageView(image: UIImage(systemName: "photo"))

    private var textOnlyConstraints: [NSLayoutConstraint] = []
    private var portraitConstraints: [NSLayoutConstraint] = []
    private var landscapeConstraints: [NSLayoutConstraint] = []
    private var activeLayoutConstraints: [NSLayoutConstraint] = []
    private var portraitImageAspectConstraint: NSLayoutConstraint!
    private var portraitImageWidthConstraint: NSLayoutConstraint!
    private var sideTitleConstraints: [NSLayoutConstraint] = []
    private var defaultStackConstraints: [NSLayoutConstraint] = []
    private var sideTitleWideConstraints: [NSLayoutConstraint] = []
    private var sideTitleTextOnlyConstraints: [NSLayoutConstraint] = []
    private var previewBottomDefaultConstraint: NSLayoutConstraint!
    private var previewTrailingDefaultConstraint: NSLayoutConstraint!
    /// Preview top in the side-title variant: it must clear the image as well as
    /// the date, and its spacing collapses with the preview itself.
    private var sideTitlePreviewBelowDateConstraint: NSLayoutConstraint!
    private var sideTitlePreviewBelowImageConstraint: NSLayoutConstraint!
    private var landscapeImageWidthConstraint: NSLayoutConstraint!
    private var landscapeImageHeightConstraint: NSLayoutConstraint!
    private var commentsWidthConstraint: NSLayoutConstraint!
    private var commentsToStarSpacingConstraint: NSLayoutConstraint!
    private var audioWidthConstraint: NSLayoutConstraint!
    private var audioHeightConstraint: NSLayoutConstraint!
    private var audioToCommentsSpacingConstraint: NSLayoutConstraint!
    private var metadataFeedTitleDefaultTrailingConstraint: NSLayoutConstraint!
    private var metadataFeedTitlePortraitTrailingConstraint: NSLayoutConstraint!
    private var publicationTimeIconWidthConstraint: NSLayoutConstraint!
    private var publicationTimeIconHeightConstraint: NSLayoutConstraint!
    private var publicationTimeIconTextSpacingConstraint: NSLayoutConstraint!
    private var dateWidthConstraint: NSLayoutConstraint!
    private var defaultDateTopConstraint: NSLayoutConstraint!
    private var defaultDateTrailingConstraint: NSLayoutConstraint!
    private var landscapeDateTrailingConstraint: NSLayoutConstraint!
    private var compactDateTrailingConstraint: NSLayoutConstraint!
    private var portraitDateTrailingConstraint: NSLayoutConstraint!
    private var sideTitleDateTrailingConstraint: NSLayoutConstraint!
    private var sideTitleWideDateTrailingConstraint: NSLayoutConstraint!
    private var sideTitleTextOnlyDateTrailingConstraint: NSLayoutConstraint!
    private var compactReadingContainerTrailingConstraint: NSLayoutConstraint!
    private var portraitReadingContainerTrailingConstraint: NSLayoutConstraint!
    private var sideTitleReadingContainerTrailingConstraint: NSLayoutConstraint!
    private var sideTitleWideReadingContainerTrailingConstraint: NSLayoutConstraint!
    private var sideTitleTextOnlyReadingContainerTrailingConstraint: NSLayoutConstraint!
    private var landscapeReadingContainerWidthConstraint: NSLayoutConstraint!
    private var landscapeReadingIconWidthConstraint: NSLayoutConstraint!
    private var landscapeReadingIconHeightConstraint: NSLayoutConstraint!
    private var landscapeReadingLabelWidthConstraint: NSLayoutConstraint!
    /// One step more contrast than `secondaryLabel` without reaching full
    /// `label`, which would compete with the headline. Resolved per trait
    /// collection so it still inverts in dark mode.
    /// A fixed alpha would cap what "Increase Contrast" can give back: the
    /// resolved base already carries the high-contrast variant, but multiplying
    /// it down again takes part of that away. Under high contrast the supporting
    /// text therefore runs at full strength.
    private static let supportingTextColor = UIColor { traits in
        let alpha: CGFloat = traits.accessibilityContrast == .high ? 1 : 0.8
        return UIColor.label.resolvedColor(with: traits).withAlphaComponent(alpha)
    }
    /// Read articles dim by the same proportion as the headline, so the whole
    /// row recedes together instead of only its title.
    private static let supportingReadTextColor = UIColor { traits in
        let alpha: CGFloat = traits.accessibilityContrast == .high ? 0.75 : 0.5
        return UIColor.label.resolvedColor(with: traits).withAlphaComponent(alpha)
    }
    private var previewTopConstraint: NSLayoutConstraint!
    private var previewCollapseConstraint: NSLayoutConstraint!
    /// Driven from the prepared metrics, so the cell cannot disagree with the
    /// engine about how large a scaled glyph slot is.
    private var accessoryConstraints: [NSLayoutConstraint] = []
    private var metadataMinimumHeight: NSLayoutConstraint!
    private var unreadWidth: NSLayoutConstraint!
    private var unreadHeight: NSLayoutConstraint!
    private var feedIconWidth: NSLayoutConstraint!
    private var feedIconHeight: NSLayoutConstraint!
    private var starWidth: NSLayoutConstraint!
    private var starHeight: NSLayoutConstraint!
    private var commentsHeightConstraint: NSLayoutConstraint!
    private var currentLayoutVariant: IOSUIKitArticleCellLayoutVariant?
    private var imageTask: Task<Void, Never>?
    private var representedImageRequest: ArticleImageRequest?
    private var articleImagePipeline = ArticleImagePipeline.shared
    private var imageBindingGeneration: UInt64 = 0
    private var currentTitle = ""
    private var currentFeedTitle = ""
    private var currentPublishedDate = ""
    private var currentShowsRelativePublicationTime = false
    private var currentReadingTime: String?
    private var currentIsRead = false
    private var currentIsStarred = false
    private var currentHasComments = false
    private var currentHasAudio = false
    /// Late image arrivals normally fade in. The timeline disables that
    /// transition while the table is actively moving so image pixels still
    /// appear immediately without adding overlapping Core Animation work.
    private var articleImageArrivalAnimationsEnabled = true
    private(set) var preparedLayoutMetrics: IOSUIKitArticleLayoutMetrics?

    weak var performanceMetrics: IOSUIKitTimelinePerformanceMetrics?
    /// Narrow decoded-scale test seam; there is no production renderer switch.
    var articleImageRasterScale: (CGFloat) -> CGFloat = { $0 }
    private(set) var representedArticleID: Int64?
    private(set) var layoutVariantRevision: UInt64 = 0
    private(set) var measurementSolveCount = 0

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .systemBackground
        contentView.backgroundColor = .systemBackground
        contentView.isOpaque = true
        contentView.preservesSuperviewLayoutMargins = false
        selectionStyle = .default

        textContainer.translatesAutoresizingMaskIntoConstraints = false
        textContainer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        // The engine owns the row height, so a cell can carry slack its natural
        // content does not fill — in the side-title variant whenever the image is
        // taller than the title-and-date column. Without a firm hugging priority
        // Auto Layout absorbs that slack into these labels, which pushes the date
        // away from the headline it belongs to. Let it land in the gap above the
        // preview instead, which is where the engine put it.
        titleLabel.setContentHuggingPriority(UILayoutPriority(999), for: .vertical)
        dateLabel.setContentHuggingPriority(UILayoutPriority(999), for: .vertical)
        starImageView.tintColor = .systemYellow
        starImageView.alpha = 0
        starImageView.isAccessibilityElement = false
        metadataRow.translatesAutoresizingMaskIntoConstraints = false
        metadataMinimumHeight = metadataRow.heightAnchor.constraint(greaterThanOrEqualToConstant: IOSUIKitArticleGeometry.feedIconSize)
        metadataMinimumHeight.isActive = true

        unreadIndicator.translatesAutoresizingMaskIntoConstraints = false
        unreadIndicator.backgroundColor = .tintColor
        unreadWidth = unreadIndicator.widthAnchor.constraint(equalToConstant: IOSUIKitArticleGeometry.unreadSize)
        unreadHeight = unreadIndicator.heightAnchor.constraint(equalToConstant: IOSUIKitArticleGeometry.unreadSize)
        NSLayoutConstraint.activate([unreadWidth, unreadHeight])

        feedIconContainer.translatesAutoresizingMaskIntoConstraints = false
        feedIconWidth = feedIconContainer.widthAnchor.constraint(equalToConstant: IOSFeedIconImagePreparation.displaySidePoints)
        feedIconHeight = feedIconContainer.heightAnchor.constraint(equalToConstant: IOSFeedIconImagePreparation.displaySidePoints)
        NSLayoutConstraint.activate([feedIconWidth, feedIconHeight])
        feedIconImageView.translatesAutoresizingMaskIntoConstraints = false
        feedIconImageView.contentMode = .scaleAspectFit
        feedIconFallbackLabel.translatesAutoresizingMaskIntoConstraints = false
        feedIconFallbackLabel.font = .preferredFont(forTextStyle: .caption2).bold()
        feedIconFallbackLabel.adjustsFontForContentSizeCategory = true
        feedIconFallbackLabel.textAlignment = .center
        feedIconFallbackLabel.textColor = .white
        feedIconContainer.addSubview(feedIconImageView)
        feedIconContainer.addSubview(feedIconFallbackLabel)
        NSLayoutConstraint.activate([
            feedIconImageView.leadingAnchor.constraint(equalTo: feedIconContainer.leadingAnchor),
            feedIconImageView.trailingAnchor.constraint(equalTo: feedIconContainer.trailingAnchor),
            feedIconImageView.topAnchor.constraint(equalTo: feedIconContainer.topAnchor),
            feedIconImageView.bottomAnchor.constraint(equalTo: feedIconContainer.bottomAnchor),
            feedIconFallbackLabel.leadingAnchor.constraint(equalTo: feedIconContainer.leadingAnchor),
            feedIconFallbackLabel.trailingAnchor.constraint(equalTo: feedIconContainer.trailingAnchor),
            feedIconFallbackLabel.topAnchor.constraint(equalTo: feedIconContainer.topAnchor),
            feedIconFallbackLabel.bottomAnchor.constraint(equalTo: feedIconContainer.bottomAnchor),
        ])

        feedTitleLabel.font = .preferredFont(forTextStyle: .subheadline).bold()
        feedTitleLabel.adjustsFontForContentSizeCategory = true
        feedTitleLabel.textColor = Self.supportingTextColor
        feedTitleLabel.lineBreakMode = .byTruncatingTail
        feedTitleLabel.numberOfLines = 1
        feedTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        audioContainer.translatesAutoresizingMaskIntoConstraints = false
        audioImageView.translatesAutoresizingMaskIntoConstraints = false
        audioImageView.tintColor = Self.supportingTextColor
        audioImageView.contentMode = .scaleAspectFit
        audioContainer.addSubview(audioImageView)
        NSLayoutConstraint.activate([
            audioImageView.centerXAnchor.constraint(equalTo: audioContainer.centerXAnchor),
            audioImageView.centerYAnchor.constraint(equalTo: audioContainer.centerYAnchor),
        ])

        commentsContainer.translatesAutoresizingMaskIntoConstraints = false
        commentsImageView.translatesAutoresizingMaskIntoConstraints = false
        commentsImageView.tintColor = Self.supportingTextColor
        commentsContainer.addSubview(commentsImageView)
        NSLayoutConstraint.activate([
            commentsImageView.centerXAnchor.constraint(equalTo: commentsContainer.centerXAnchor),
            commentsImageView.centerYAnchor.constraint(equalTo: commentsContainer.centerYAnchor),
        ])

        starImageView.translatesAutoresizingMaskIntoConstraints = false
        publicationTimeIconView.translatesAutoresizingMaskIntoConstraints = false
        publicationTimeIconView.tintColor = Self.supportingTextColor
        publicationTimeIconView.contentMode = .scaleAspectFit
        publicationTimeIconView.isHidden = true
        publicationTimeIconWidthConstraint = publicationTimeIconView.widthAnchor.constraint(equalToConstant: 0)
        publicationTimeIconHeightConstraint = publicationTimeIconView.heightAnchor.constraint(equalToConstant: 0)

        dateLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        dateLabel.adjustsFontForContentSizeCategory = true
        dateLabel.textColor = Self.supportingTextColor
        dateLabel.numberOfLines = 1
        dateLabel.lineBreakMode = .byTruncatingTail
        // The deterministic engine owns the exact publication width. This keeps
        // the optional reading-time group immediately adjacent instead of letting
        // the date label expand across all remaining horizontal space.
        dateWidthConstraint = dateLabel.widthAnchor.constraint(equalToConstant: 0)

        landscapeReadingTimeContainer.translatesAutoresizingMaskIntoConstraints = false
        landscapeReadingTimeContainer.isHidden = true
        landscapeReadingTimeIconView.translatesAutoresizingMaskIntoConstraints = false
        landscapeReadingTimeIconView.tintColor = Self.supportingTextColor
        landscapeReadingTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        landscapeReadingTimeLabel.font = .preferredFont(forTextStyle: .caption1)
        landscapeReadingTimeLabel.adjustsFontForContentSizeCategory = true
        landscapeReadingTimeLabel.textColor = Self.supportingTextColor
        landscapeReadingTimeLabel.numberOfLines = 1
        landscapeReadingTimeContainer.addSubview(landscapeReadingTimeIconView)
        landscapeReadingTimeContainer.addSubview(landscapeReadingTimeLabel)
        landscapeReadingContainerWidthConstraint = landscapeReadingTimeContainer.widthAnchor.constraint(equalToConstant: 0)
        landscapeReadingIconWidthConstraint = landscapeReadingTimeIconView.widthAnchor.constraint(equalToConstant: 0)
        landscapeReadingIconHeightConstraint = landscapeReadingTimeIconView.heightAnchor.constraint(equalToConstant: 0)
        landscapeReadingLabelWidthConstraint = landscapeReadingTimeLabel.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            landscapeReadingContainerWidthConstraint,
            landscapeReadingTimeIconView.leadingAnchor.constraint(equalTo: landscapeReadingTimeContainer.leadingAnchor),
            landscapeReadingTimeIconView.centerYAnchor.constraint(equalTo: landscapeReadingTimeContainer.centerYAnchor),
            landscapeReadingIconWidthConstraint,
            landscapeReadingIconHeightConstraint,
            landscapeReadingTimeLabel.leadingAnchor.constraint(
                equalTo: landscapeReadingTimeIconView.trailingAnchor,
                constant: IOSUIKitArticleGeometry.landscapeReadingTimeIconTextSpacing
            ),
            landscapeReadingTimeLabel.trailingAnchor.constraint(equalTo: landscapeReadingTimeContainer.trailingAnchor),
            landscapeReadingTimeLabel.topAnchor.constraint(equalTo: landscapeReadingTimeContainer.topAnchor),
            landscapeReadingTimeLabel.bottomAnchor.constraint(equalTo: landscapeReadingTimeContainer.bottomAnchor),
            landscapeReadingLabelWidthConstraint,
        ])

        metadataRow.addSubview(unreadIndicator)
        metadataRow.addSubview(feedIconContainer)
        metadataRow.addSubview(feedTitleLabel)
        metadataRow.addSubview(audioContainer)
        metadataRow.addSubview(commentsContainer)
        metadataRow.addSubview(starImageView)
        audioWidthConstraint = audioContainer.widthAnchor.constraint(equalToConstant: 0)
        audioHeightConstraint = audioContainer.heightAnchor.constraint(equalToConstant: IOSUIKitArticleGeometry.commentSlotSize)
        commentsWidthConstraint = commentsContainer.widthAnchor.constraint(equalToConstant: 0)
        commentsHeightConstraint = commentsContainer.heightAnchor.constraint(equalToConstant: IOSUIKitArticleGeometry.commentSlotSize)
        starWidth = starImageView.widthAnchor.constraint(equalToConstant: IOSUIKitArticleGeometry.starSlotSize)
        starHeight = starImageView.heightAnchor.constraint(equalToConstant: IOSUIKitArticleGeometry.starSlotSize)
        commentsToStarSpacingConstraint = commentsContainer.trailingAnchor.constraint(equalTo: starImageView.leadingAnchor)
        audioToCommentsSpacingConstraint = audioContainer.trailingAnchor.constraint(equalTo: commentsContainer.leadingAnchor)
        metadataFeedTitleDefaultTrailingConstraint = feedTitleLabel.trailingAnchor.constraint(
            equalTo: audioContainer.leadingAnchor,
            constant: -IOSUIKitArticleGeometry.metadataTitleSpacing
        )
        metadataFeedTitlePortraitTrailingConstraint = feedTitleLabel.trailingAnchor.constraint(equalTo: metadataRow.trailingAnchor)
        NSLayoutConstraint.activate([
            // Leading edge: feed icon, then the feed name.
            feedIconContainer.leadingAnchor.constraint(equalTo: metadataRow.leadingAnchor),
            feedIconContainer.centerYAnchor.constraint(equalTo: metadataRow.centerYAnchor),
            // Trailing edge, outermost first: unread dot, then star.
            unreadIndicator.trailingAnchor.constraint(equalTo: metadataRow.trailingAnchor),
            unreadIndicator.centerYAnchor.constraint(equalTo: metadataRow.centerYAnchor),
            feedTitleLabel.leadingAnchor.constraint(equalTo: feedIconContainer.trailingAnchor, constant: IOSUIKitArticleGeometry.metadataLeadingSpacing),
            metadataFeedTitleDefaultTrailingConstraint,
            feedTitleLabel.topAnchor.constraint(equalTo: metadataRow.topAnchor),
            feedTitleLabel.bottomAnchor.constraint(equalTo: metadataRow.bottomAnchor),
            audioContainer.centerYAnchor.constraint(equalTo: metadataRow.centerYAnchor),
            audioWidthConstraint,
            audioHeightConstraint,
            audioToCommentsSpacingConstraint,
            commentsContainer.centerYAnchor.constraint(equalTo: metadataRow.centerYAnchor),
            commentsWidthConstraint,
            commentsHeightConstraint,
            commentsToStarSpacingConstraint,
            starImageView.trailingAnchor.constraint(
                equalTo: unreadIndicator.leadingAnchor,
                constant: -IOSUIKitArticleGeometry.metadataAccessorySpacing
            ),
            starImageView.centerYAnchor.constraint(equalTo: metadataRow.centerYAnchor),
            starWidth,
            starHeight,
        ])

        previewLabel.font = .preferredFont(forTextStyle: .subheadline)
        previewLabel.adjustsFontForContentSizeCategory = true
        previewLabel.textColor = Self.supportingTextColor
        previewLabel.numberOfLines = 3
        previewLabel.setContentHuggingPriority(UILayoutPriority(999), for: .vertical)
        previewContinuationLabel.font = .preferredFont(forTextStyle: .subheadline)
        previewContinuationLabel.adjustsFontForContentSizeCategory = true
        previewContinuationLabel.textColor = Self.supportingTextColor
        previewContinuationLabel.numberOfLines = 3
        previewContinuationLabel.translatesAutoresizingMaskIntoConstraints = false
        previewContinuationLabel.setContentHuggingPriority(UILayoutPriority(999), for: .vertical)
        sidePreviewHeightConstraint = previewLabel.heightAnchor.constraint(equalToConstant: 0)
        sidePreviewHeightConstraint.priority = UILayoutPriority(999)
        sideContinuationHeightConstraint = previewContinuationLabel.heightAnchor.constraint(equalToConstant: 0)
        sideContinuationHeightConstraint.priority = UILayoutPriority(999)

        for label in [titleLabel, dateLabel, previewLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            textContainer.addSubview(label)
        }
        textContainer.addSubview(metadataRow)
        textContainer.addSubview(publicationTimeIconView)
        textContainer.addSubview(landscapeReadingTimeContainer)
        textContainer.addSubview(previewContinuationLabel)
        previewContinuationLabel.isHidden = true
        previewTopConstraint = previewLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: IOSUIKitArticleGeometry.textSpacing)
        // Collapsing by priority keeps the constraint graph untouched. Removing
        // or deactivating it instead would mutate the graph on every reuse
        // between an article with and without a preview.
        previewCollapseConstraint = previewLabel.heightAnchor.constraint(equalToConstant: 0)
        previewCollapseConstraint.priority = .defaultHigh
        previewCollapseConstraint.isActive = true
        // The side-title
        // variant reorders the text block and narrows part of it, so the
        // vertical order and the trailing edges are owned by the variant groups.
        // Only the leading edge and the container's bottom are shared.
        previewBottomDefaultConstraint = previewLabel.bottomAnchor.constraint(equalTo: textContainer.bottomAnchor)
        previewTrailingDefaultConstraint = previewLabel.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor)

        defaultDateTopConstraint = dateLabel.topAnchor.constraint(
            equalTo: titleLabel.bottomAnchor,
            constant: IOSUIKitArticleGeometry.textSpacing
        )
        defaultDateTrailingConstraint = dateLabel.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor)
        defaultStackConstraints = [
            previewBottomDefaultConstraint,
            previewTrailingDefaultConstraint,
            metadataRow.topAnchor.constraint(equalTo: textContainer.topAnchor),
            metadataRow.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: metadataRow.bottomAnchor, constant: IOSUIKitArticleGeometry.textSpacing),
            titleLabel.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor),
            defaultDateTopConstraint,
            defaultDateTrailingConstraint,
            previewTopConstraint,
        ]

        publicationTimeIconTextSpacingConstraint = dateLabel.leadingAnchor.constraint(
            equalTo: publicationTimeIconView.trailingAnchor,
            constant: 0
        )
        var stackedConstraints: [NSLayoutConstraint] = [
            publicationTimeIconView.leadingAnchor.constraint(equalTo: textContainer.leadingAnchor),
            publicationTimeIconView.centerYAnchor.constraint(equalTo: dateLabel.centerYAnchor),
            publicationTimeIconWidthConstraint,
            publicationTimeIconHeightConstraint,
            publicationTimeIconTextSpacingConstraint,
            dateWidthConstraint,
        ]
        for child in [titleLabel, metadataRow, previewLabel] as [UIView] {
            stackedConstraints.append(child.leadingAnchor.constraint(equalTo: textContainer.leadingAnchor))
        }
        NSLayoutConstraint.activate(stackedConstraints)

        articleImageView.translatesAutoresizingMaskIntoConstraints = false
        articleImageView.isHidden = true
        imagePlaceholder.translatesAutoresizingMaskIntoConstraints = false
        imagePlaceholder.tintColor = Self.supportingTextColor
        imagePlaceholder.contentMode = .center
        articleImageView.addSubview(imagePlaceholder)
        NSLayoutConstraint.activate([
            imagePlaceholder.centerXAnchor.constraint(equalTo: articleImageView.centerXAnchor),
            imagePlaceholder.centerYAnchor.constraint(equalTo: articleImageView.centerYAnchor),
        ])

        contentView.addSubview(textContainer)
        contentView.addSubview(articleImageView)
        preparePermanentLayoutConstraints()
        setArticleImagePresentation(loaded: false)
        setFeedIconPresentation(loaded: false)

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = String(localized: "Opens the article")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func preparePermanentLayoutConstraints() {
        let margins = contentView.layoutMarginsGuide
        portraitImageAspectConstraint = articleImageView.heightAnchor.constraint(
            equalTo: articleImageView.widthAnchor,
            multiplier: 1 / ArticlePresentationLayout.portraitImageAspectRatio
        )
        portraitImageWidthConstraint = articleImageView.widthAnchor.constraint(equalToConstant: 1)
        landscapeImageWidthConstraint = articleImageView.widthAnchor.constraint(equalToConstant: 1)
        landscapeImageHeightConstraint = articleImageView.heightAnchor.constraint(equalToConstant: 1)
        compactDateTrailingConstraint = dateLabel.trailingAnchor.constraint(
            equalTo: landscapeReadingTimeContainer.leadingAnchor,
            constant: -IOSUIKitArticleGeometry.landscapeDateReadingTimeSpacing
        )
        compactReadingContainerTrailingConstraint = landscapeReadingTimeContainer.trailingAnchor.constraint(
            lessThanOrEqualTo: textContainer.trailingAnchor
        )
        let compactStackConstraints = defaultStackConstraints.filter {
            $0 !== defaultDateTrailingConstraint
        }
        textOnlyConstraints = compactStackConstraints + [
            compactDateTrailingConstraint,
            compactReadingContainerTrailingConstraint,
            landscapeReadingTimeContainer.topAnchor.constraint(equalTo: dateLabel.topAnchor),
            landscapeReadingTimeContainer.bottomAnchor.constraint(equalTo: dateLabel.bottomAnchor),

            textContainer.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            textContainer.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            textContainer.topAnchor.constraint(equalTo: margins.topAnchor),
            textContainer.bottomAnchor.constraint(equalTo: margins.bottomAnchor),
        ]
        // Standard Visual portrait:
        //
        //   ┌─────────────────────┐
        //   │   HERO IMAGE 100%   │
        //   └─────────────────────┘
        //   ● icon  Feed name              ★ 💬
        //   Headline
        //   Date · ▤ 4 min
        //   Preview …
        //
        // Full-width image followed by the normal metadata/title/date stack.
        portraitDateTrailingConstraint = dateLabel.trailingAnchor.constraint(
            equalTo: landscapeReadingTimeContainer.leadingAnchor,
            constant: -IOSUIKitArticleGeometry.landscapeDateReadingTimeSpacing
        )
        portraitReadingContainerTrailingConstraint = landscapeReadingTimeContainer.trailingAnchor.constraint(
            lessThanOrEqualTo: textContainer.trailingAnchor
        )
        portraitConstraints = [
            articleImageView.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            articleImageView.topAnchor.constraint(equalTo: margins.topAnchor),
            portraitImageWidthConstraint,
            portraitImageAspectConstraint,

            textContainer.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            textContainer.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            textContainer.topAnchor.constraint(
                equalTo: articleImageView.bottomAnchor,
                constant: IOSUIKitArticleGeometry.portraitSpacing
            ),
            textContainer.bottomAnchor.constraint(equalTo: margins.bottomAnchor),

            metadataRow.topAnchor.constraint(equalTo: textContainer.topAnchor),
            metadataRow.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor),

            titleLabel.topAnchor.constraint(
                equalTo: metadataRow.bottomAnchor,
                constant: IOSUIKitArticleGeometry.textSpacing
            ),
            titleLabel.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor),

            dateLabel.topAnchor.constraint(
                equalTo: titleLabel.bottomAnchor,
                constant: IOSUIKitArticleGeometry.textSpacing
            ),
            portraitDateTrailingConstraint,
            portraitReadingContainerTrailingConstraint,
            landscapeReadingTimeContainer.topAnchor.constraint(equalTo: dateLabel.topAnchor),
            landscapeReadingTimeContainer.bottomAnchor.constraint(equalTo: dateLabel.bottomAnchor),

            previewTopConstraint,
            previewTrailingDefaultConstraint,
            previewBottomDefaultConstraint,
        ]

        landscapeDateTrailingConstraint = dateLabel.trailingAnchor.constraint(
            equalTo: landscapeReadingTimeContainer.leadingAnchor,
            constant: -IOSUIKitArticleGeometry.landscapeDateReadingTimeSpacing
        )

        let landscapeStackConstraints = defaultStackConstraints.filter {
            $0 !== defaultDateTrailingConstraint
        }
        landscapeConstraints = landscapeStackConstraints + [
            landscapeDateTrailingConstraint,

            articleImageView.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            articleImageView.topAnchor.constraint(equalTo: margins.topAnchor),
            landscapeImageWidthConstraint,
            landscapeImageHeightConstraint,
            articleImageView.bottomAnchor.constraint(lessThanOrEqualTo: margins.bottomAnchor),
            textContainer.leadingAnchor.constraint(equalTo: articleImageView.trailingAnchor, constant: 14),
            textContainer.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            textContainer.topAnchor.constraint(equalTo: margins.topAnchor),
            textContainer.bottomAnchor.constraint(lessThanOrEqualTo: margins.bottomAnchor),

            landscapeReadingTimeContainer.trailingAnchor.constraint(lessThanOrEqualTo: textContainer.trailingAnchor),
            landscapeReadingTimeContainer.topAnchor.constraint(equalTo: dateLabel.topAnchor),
            landscapeReadingTimeContainer.bottomAnchor.constraint(equalTo: dateLabel.bottomAnchor),
        ]

        // Image-bearing Visual Compact: preview begins below publication
        // beside the thumbnail, with a full-width continuation underneath.
        sideTitleDateTrailingConstraint = dateLabel.trailingAnchor.constraint(
            equalTo: landscapeReadingTimeContainer.leadingAnchor,
            constant: -IOSUIKitArticleGeometry.landscapeDateReadingTimeSpacing
        )
        sideTitleReadingContainerTrailingConstraint = landscapeReadingTimeContainer.trailingAnchor.constraint(
            lessThanOrEqualTo: articleImageView.leadingAnchor,
            constant: -IOSUIKitArticleGeometry.sideTitleSpacing
        )
        sideTitleWideDateTrailingConstraint = dateLabel.trailingAnchor.constraint(
            equalTo: landscapeReadingTimeContainer.leadingAnchor,
            constant: -IOSUIKitArticleGeometry.landscapeDateReadingTimeSpacing
        )
        sideTitleWideReadingContainerTrailingConstraint = landscapeReadingTimeContainer.trailingAnchor.constraint(
            lessThanOrEqualTo: articleImageView.leadingAnchor,
            constant: -IOSUIKitArticleGeometry.sideTitleSpacing
        )
        sideTitlePreviewBelowDateConstraint = previewLabel.topAnchor.constraint(
            equalTo: dateLabel.bottomAnchor, constant: IOSUIKitArticleGeometry.textSpacing
        )
        sideTitlePreviewBelowImageConstraint = previewLabel.topAnchor.constraint(
            greaterThanOrEqualTo: articleImageView.bottomAnchor
        )
        sideContinuationTopConstraint = previewContinuationLabel.topAnchor.constraint(
            equalTo: articleImageView.bottomAnchor,
            constant: IOSUIKitArticleGeometry.textSpacing
        )
        let sideFlowConstraints: [NSLayoutConstraint] = [
            textContainer.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            textContainer.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            textContainer.topAnchor.constraint(equalTo: margins.topAnchor),
            textContainer.bottomAnchor.constraint(equalTo: margins.bottomAnchor),
            metadataRow.topAnchor.constraint(equalTo: textContainer.topAnchor),
            metadataRow.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor),
            titleLabel.topAnchor.constraint(
                equalTo: metadataRow.bottomAnchor, constant: IOSUIKitArticleGeometry.textSpacing
            ),
            titleLabel.trailingAnchor.constraint(
                equalTo: articleImageView.leadingAnchor,
                constant: -IOSUIKitArticleGeometry.sideTitleSpacing
            ),
            dateLabel.topAnchor.constraint(
                equalTo: titleLabel.bottomAnchor, constant: IOSUIKitArticleGeometry.textSpacing
            ),
            landscapeReadingTimeContainer.topAnchor.constraint(equalTo: dateLabel.topAnchor),
            landscapeReadingTimeContainer.bottomAnchor.constraint(equalTo: dateLabel.bottomAnchor),
            articleImageView.topAnchor.constraint(
                equalTo: metadataRow.bottomAnchor, constant: IOSUIKitArticleGeometry.textSpacing
            ),
            articleImageView.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor),
            landscapeImageWidthConstraint,
            landscapeImageHeightConstraint,
            sideTitlePreviewBelowDateConstraint,
            previewLabel.trailingAnchor.constraint(
                equalTo: articleImageView.leadingAnchor,
                constant: -IOSUIKitArticleGeometry.sideTitleSpacing
            ),
            sidePreviewHeightConstraint,
            previewContinuationLabel.leadingAnchor.constraint(equalTo: textContainer.leadingAnchor),
            previewContinuationLabel.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor),
            sideContinuationTopConstraint,
            sideContinuationHeightConstraint,
            // Restore the vertical content chain used by UIKit compressed-size
            // tests. Without these bounds, Auto Layout can collapse an
            // image-bearing row to the metadata height (~30 pt), even though
            // the precomputed row height correctly includes its thumbnail.
            articleImageView.bottomAnchor.constraint(lessThanOrEqualTo: textContainer.bottomAnchor),
            dateLabel.bottomAnchor.constraint(lessThanOrEqualTo: textContainer.bottomAnchor),
            previewLabel.bottomAnchor.constraint(lessThanOrEqualTo: textContainer.bottomAnchor),
            previewContinuationLabel.bottomAnchor.constraint(lessThanOrEqualTo: textContainer.bottomAnchor),
        ]
        sideTitleConstraints = sideFlowConstraints + [
            sideTitleDateTrailingConstraint, sideTitleReadingContainerTrailingConstraint,
        ]
        sideTitleWideConstraints = sideTitleConstraints

        // `Visual compact` without an image: the same order — metadata bar,
        // then title, date, preview — at full width, with no image slot.
        sideTitleTextOnlyDateTrailingConstraint = dateLabel.trailingAnchor.constraint(
            equalTo: landscapeReadingTimeContainer.leadingAnchor,
            constant: -IOSUIKitArticleGeometry.landscapeDateReadingTimeSpacing
        )
        sideTitleTextOnlyReadingContainerTrailingConstraint = landscapeReadingTimeContainer.trailingAnchor.constraint(
            lessThanOrEqualTo: textContainer.trailingAnchor
        )
        sideTitleTextOnlyConstraints = [
            textContainer.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            textContainer.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            textContainer.topAnchor.constraint(equalTo: margins.topAnchor),
            textContainer.bottomAnchor.constraint(equalTo: margins.bottomAnchor),

            metadataRow.topAnchor.constraint(equalTo: textContainer.topAnchor),
            metadataRow.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor),

            titleLabel.topAnchor.constraint(equalTo: metadataRow.bottomAnchor, constant: IOSUIKitArticleGeometry.textSpacing),
            titleLabel.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor),
            dateLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: IOSUIKitArticleGeometry.textSpacing),
            sideTitleTextOnlyDateTrailingConstraint,
            sideTitleTextOnlyReadingContainerTrailingConstraint,
            landscapeReadingTimeContainer.topAnchor.constraint(equalTo: dateLabel.topAnchor),
            landscapeReadingTimeContainer.bottomAnchor.constraint(equalTo: dateLabel.bottomAnchor),

            previewTopConstraint,
            previewBottomDefaultConstraint,
            previewTrailingDefaultConstraint,
        ]
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        performanceMetrics?.recordReuse()
        invalidateImageBinding()
        representedImageRequest = nil
        representedArticleID = nil
        preparedLayoutMetrics = nil
        previewContinuationLabel.text = nil
        previewContinuationLabel.isHidden = true
        clearArticleImagePresentation()
    }

    func configure(
        item: IOSUIKitArticleTimelineItem,
        hasAudio: Bool = false,
        mode: ArticlePresentationMode,
        previewLines: ArticlePreviewLines,
        showRelativePublicationTime: Bool = false,
        displayScale: CGFloat,
        preparedLayoutMetrics: IOSUIKitArticleLayoutMetrics
    ) {
        let articleChanged = representedArticleID != item.article.id
        representedArticleID = item.article.id
        // Keep independently constrained content in the cell's semantic direction.
        // This is explicit because forced RTL test/preview environments do not
        // reliably propagate through UITableViewCell.contentView on every OS.
        metadataRow.semanticContentAttribute = semanticContentAttribute
        textContainer.semanticContentAttribute = semanticContentAttribute
        self.preparedLayoutMetrics = preparedLayoutMetrics
        currentTitle = item.content.article.title
        currentFeedTitle = item.content.article.feedTitle
        currentShowsRelativePublicationTime = showRelativePublicationTime
        currentPublishedDate = showRelativePublicationTime ? item.content.publishedAge : item.content.publishedDate
        currentReadingTime = item.content.readingTime
        updateAudioAvailability(hasAudio)
        titleLabel.text = currentTitle
        feedTitleLabel.text = currentFeedTitle
        dateLabel.text = item.content.readingTime == nil
            ? currentPublishedDate
            : "\(currentPublishedDate) ·"
        landscapeReadingTimeLabel.text = item.content.readingTime
        let hasPreview = !item.content.article.preview.isEmpty
        let imageSideFlow = preparedLayoutMetrics.variant == .visualSideTitle
            || preparedLayoutMetrics.variant == .visualSideTitleWide
        previewLabel.text = imageSideFlow
            ? preparedLayoutMetrics.previewSideText : item.content.article.preview
        previewLabel.isHidden = !hasPreview
            || (imageSideFlow && preparedLayoutMetrics.previewFrame == nil)
        previewLabel.numberOfLines = previewLines.rawValue
        previewContinuationLabel.text = imageSideFlow
            ? preparedLayoutMetrics.previewContinuationText : nil
        previewContinuationLabel.isHidden = !imageSideFlow
            || preparedLayoutMetrics.previewContinuationFrame == nil
        previewContinuationLabel.numberOfLines = previewLines.rawValue
        sidePreviewHeightConstraint.constant = imageSideFlow
            ? (preparedLayoutMetrics.previewFrame?.height ?? 0) : 0
        sideContinuationHeightConstraint.constant =
            preparedLayoutMetrics.previewContinuationFrame?.height ?? 0
        sideContinuationTopConstraint.constant = {
            guard let continuation = preparedLayoutMetrics.previewContinuationFrame,
                  let image = preparedLayoutMetrics.imageFrame else { return 0 }
            return continuation.minY - image.maxY
        }()
        // Constants and priorities only — the constraint graph stays identical
        // across every reuse, whatever the article contains.
        previewTopConstraint.constant = hasPreview ? IOSUIKitArticleGeometry.textSpacing : 0
        // Same collapse for the
        // side-title variant's pair, or a preview-less row keeps a gap below the
        // image that the engine did not budget for.
        let previewSpacing = hasPreview ? IOSUIKitArticleGeometry.textSpacing : 0
        sideTitlePreviewBelowDateConstraint.constant = previewSpacing
        sideTitlePreviewBelowImageConstraint.constant = previewSpacing
        previewCollapseConstraint.priority = hasPreview ? UILayoutPriority(1) : .defaultHigh
        let hasComments = item.content.hasComments
        currentHasComments = hasComments
        commentsContainer.isHidden = !hasComments
        commentsWidthConstraint.constant = hasComments ? (preparedLayoutMetrics.commentsFrame?.width ?? IOSUIKitArticleGeometry.commentSlotSize) : 0
        commentsToStarSpacingConstraint.constant = hasComments ? -IOSUIKitArticleGeometry.metadataAccessorySpacing : 0
        let hasImage = mode.showsArticleImage && item.content.imageURL != nil
        let imageSize = hasImage ? (preparedLayoutMetrics.imageFrame?.size ?? .zero) : .zero
        applyLayout(preparedLayoutMetrics)

        updateFeedIcon(image: item.feedIconImage, title: item.content.article.feedTitle)
        updateStatus(isRead: item.isRead, isStarred: item.isStarred)
        configureArticleImage(
            url: item.content.imageURL,
            targetSize: imageSize,
            displayScale: displayScale,
            articleChanged: articleChanged
        )
        contentView.setNeedsLayout()
    }

    /// Slot sizes come from the prepared metrics rather than from constants, so
    /// the scaled glyphs and the engine's frames cannot drift apart.
    private func applyAccessoryMetrics(_ layout: IOSUIKitArticleLayoutMetrics) {
        let unread = layout.unreadFrame.width
        if unreadWidth.constant != unread {
            unreadWidth.constant = unread
            unreadHeight.constant = unread
        }
        // Guarded on its own value, not on the size: at the default text size the
        // computed width equals the constant the constraint was created with, so
        // folding this into the branch above left the radius at 0 and the dot
        // rendered as a square.
        let unreadRadius = unread / 2
        if unreadIndicator.layer.cornerRadius != unreadRadius {
            unreadIndicator.layer.cornerRadius = unreadRadius
        }
        let icon = layout.feedIconFrame.width
        if feedIconWidth.constant != icon {
            feedIconWidth.constant = icon
            feedIconHeight.constant = icon
            metadataMinimumHeight.constant = icon
        }
        let star = layout.starFrame.width
        if starWidth.constant != star {
            starWidth.constant = star
            starHeight.constant = star
        }
        let comments = layout.commentsFrame?.width ?? IOSUIKitArticleGeometry.commentSlotSize
        if commentsHeightConstraint.constant != comments {
            commentsHeightConstraint.constant = comments
        }

        if let publicationIcon = layout.publicationTimeIconFrame {
            publicationTimeIconWidthConstraint.constant = publicationIcon.width
            publicationTimeIconHeightConstraint.constant = publicationIcon.height
        } else {
            publicationTimeIconWidthConstraint.constant = 0
            publicationTimeIconHeightConstraint.constant = 0
        }
        dateWidthConstraint.constant = layout.dateFrame.width

        if let container = layout.landscapeReadingTimeContainerFrame,
           let icon = layout.landscapeReadingTimeIconFrame,
           let text = layout.landscapeReadingTimeFrame {
            landscapeReadingContainerWidthConstraint.constant = container.width
            landscapeReadingIconWidthConstraint.constant = icon.width
            landscapeReadingIconHeightConstraint.constant = icon.height
            landscapeReadingLabelWidthConstraint.constant = text.width
        } else {
            landscapeReadingContainerWidthConstraint.constant = 0
            landscapeReadingIconWidthConstraint.constant = 0
            landscapeReadingIconHeightConstraint.constant = 0
            landscapeReadingLabelWidthConstraint.constant = 0
        }
    }

    private func applyLayout(_ layout: IOSUIKitArticleLayoutMetrics) {
        applyAccessoryMetrics(layout)
        let variant = layout.variant
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: layout.verticalInset,
            leading: layout.horizontalInset,
            bottom: layout.verticalInset,
            trailing: layout.horizontalInset
        )

        let usesDateRowReadingTime = currentReadingTime != nil
        publicationTimeIconView.isHidden = !currentShowsRelativePublicationTime
        publicationTimeIconTextSpacingConstraint.constant = currentShowsRelativePublicationTime
            ? IOSUIKitArticleGeometry.landscapeReadingTimeIconTextSpacing
            : 0
        metadataFeedTitleDefaultTrailingConstraint.isActive = true
        metadataFeedTitlePortraitTrailingConstraint.isActive = false
        landscapeReadingTimeContainer.isHidden = !usesDateRowReadingTime
        let dateReadingSpacing = usesDateRowReadingTime
            ? -IOSUIKitArticleGeometry.landscapeDateReadingTimeSpacing
            : 0
        landscapeDateTrailingConstraint.constant = dateReadingSpacing
        compactDateTrailingConstraint.constant = dateReadingSpacing
        portraitDateTrailingConstraint.constant = dateReadingSpacing
        sideTitleDateTrailingConstraint.constant = dateReadingSpacing
        sideTitleWideDateTrailingConstraint.constant = dateReadingSpacing
        sideTitleTextOnlyDateTrailingConstraint.constant = dateReadingSpacing
        unreadIndicator.isHidden = false
        starImageView.isHidden = false
        commentsContainer.isHidden = !currentHasComments

        if let imageSize = layout.imageFrame?.size {
            if variant == .visualPortrait {
                portraitImageWidthConstraint.constant = imageSize.width
            } else if variant == .visualLandscape || variant == .visualSideTitle || variant == .visualSideTitleWide {
                landscapeImageWidthConstraint.constant = imageSize.width
                landscapeImageHeightConstraint.constant = imageSize.height
            }
        }

        guard currentLayoutVariant != variant else {
            articleImageView.isHidden = !variant.showsImageSlot
            return
        }

        NSLayoutConstraint.deactivate(activeLayoutConstraints)
        dateLabel.isHidden = false

        switch variant {
        case .compact, .visualTextOnly:
            activeLayoutConstraints = textOnlyConstraints
        case .visualPortrait:
            activeLayoutConstraints = portraitConstraints
        case .visualLandscape:
            activeLayoutConstraints = landscapeConstraints
        case .visualSideTitle:
            activeLayoutConstraints = sideTitleConstraints
        case .visualSideTitleWide:
            activeLayoutConstraints = sideTitleWideConstraints
        case .visualSideTitleTextOnly:
            activeLayoutConstraints = sideTitleTextOnlyConstraints
        }
        NSLayoutConstraint.activate(activeLayoutConstraints)
        currentLayoutVariant = variant
        layoutVariantRevision &+= 1
        performanceMetrics?.recordVariantSwitch()
        articleImageView.isHidden = !variant.showsImageSlot
    }

    func updateStatus(isRead: Bool, isStarred: Bool) {
        currentIsRead = isRead
        currentIsStarred = isStarred
        titleLabel.textColor = isRead ? .secondaryLabel : .label
        // Colour only — never anything that could move a frame.
        let supporting = isRead ? Self.supportingReadTextColor : Self.supportingTextColor
        feedTitleLabel.textColor = supporting
        publicationTimeIconView.tintColor = supporting
        dateLabel.textColor = supporting
        landscapeReadingTimeIconView.tintColor = supporting
        landscapeReadingTimeLabel.textColor = supporting
        previewLabel.textColor = supporting
        previewContinuationLabel.textColor = supporting
        commentsImageView.tintColor = supporting
        audioImageView.tintColor = supporting
        let unreadOpacity = ArticlePresentationLayout.internalUnreadIndicatorOpacity(isRead: isRead)
        unreadIndicator.alpha = unreadOpacity
        // The fixed trailing/rail slot remains allocated when the star is not visible.
        starImageView.alpha = isStarred ? 1 : 0
        updateAccessibility()
    }

    func updateAudioAvailability(_ hasAudio: Bool) {
        currentHasAudio = hasAudio
        audioContainer.isHidden = !hasAudio
        let slot = preparedLayoutMetrics?.starFrame.width
            ?? IOSUIKitArticleGeometry.commentSlotSize
        audioWidthConstraint.constant = hasAudio ? slot : 0
        audioHeightConstraint.constant = slot
        audioToCommentsSpacingConstraint.constant = hasAudio
            ? -IOSUIKitArticleGeometry.metadataAccessorySpacing
            : 0
        landscapeReadingTimeIconView.image = UIImage(
            systemName: hasAudio ? "headphones" : "doc.text"
        )
        contentView.setNeedsLayout()
    }

    func updateFeedIcon(image: UIImage?, title: String) {
        if let image {
            feedIconImageView.image = image
            feedIconImageView.isHidden = false
            feedIconFallbackLabel.isHidden = true
            feedIconContainer.backgroundColor = .clear
            setFeedIconPresentation(loaded: true)
        } else {
            feedIconImageView.image = nil
            feedIconImageView.isHidden = true
            feedIconFallbackLabel.isHidden = false
            feedIconFallbackLabel.text = title.prefix(1).uppercased()
            feedIconContainer.backgroundColor = .tintColor
            setFeedIconPresentation(loaded: false)
        }
    }

    // Internal test seam: pixels must remain a presentation-only update.
    func applyArticleImagePixelsForTesting(_ image: UIImage?) {
        articleImageView.image = image
        imagePlaceholder.isHidden = image != nil
        setArticleImagePresentation(loaded: image != nil)
    }

    var articleImageSlotFrameForTesting: CGRect { articleImageView.frame }
#if DEBUG
    private(set) var articleImageFadeCountForTesting = 0
    var articleImageIsFadingForTesting: Bool {
        articleImageView.layer.animation(forKey: Self.articleImageFadeKey) != nil
    }
#endif
    var articleImageForTesting: UIImage? { articleImageView.image }
    var articleImageSlotIsHiddenForTesting: Bool { articleImageView.isHidden }
#if DEBUG
    var articleImageRasterForTesting: CGImage? { articleImageView.image?.cgImage }
    func setArticleImagePipelineForTesting(_ pipeline: ArticleImagePipeline) { articleImagePipeline = pipeline }
#endif
    func setArticleImageArrivalAnimationsEnabled(_ enabled: Bool) {
        articleImageArrivalAnimationsEnabled = enabled
    }
    var articleImagePresentationForTesting: (placeholderHidden: Bool, contentMode: UIView.ContentMode, clipsToBounds: Bool, cornerRadius: CGFloat) {
        (imagePlaceholder.isHidden, articleImageView.contentMode, articleImageView.clipsToBounds, articleImageView.layer.cornerRadius)
    }
    var feedIconPresentationForTesting: (imageHidden: Bool, fallbackHidden: Bool, clipsToBounds: Bool, cornerRadius: CGFloat) {
        (feedIconImageView.isHidden, feedIconFallbackLabel.isHidden, feedIconContainer.clipsToBounds, feedIconContainer.layer.cornerRadius)
    }

    struct LayoutDiagnostics: Equatable {
        let contentBounds: CGRect
        let margins: NSDirectionalEdgeInsets
        let variant: IOSUIKitArticleCellLayoutVariant?
        let imageFrame: CGRect
        let textStackFrame: CGRect
        let titleFrame: CGRect
        let starFrame: CGRect
        let metadataFrame: CGRect
        let unreadFrame: CGRect
        let feedIconFrame: CGRect
        let feedTitleFrame: CGRect
        let commentsFrame: CGRect?
        let dateFrame: CGRect
        let publicationTimeIconFrame: CGRect?
        let landscapeReadingTimeContainerFrame: CGRect?
        let landscapeReadingTimeIconFrame: CGRect?
        let landscapeReadingTimeFrame: CGRect?
        let previewFrame: CGRect?
        let previewContinuationFrame: CGRect?
    }

    var layoutDiagnosticsForTesting: LayoutDiagnostics {
        func frame(_ view: UIView) -> CGRect { view.convert(view.bounds, to: contentView) }
        return .init(
            contentBounds: contentView.bounds,
            margins: contentView.directionalLayoutMargins,
            variant: currentLayoutVariant,
            imageFrame: frame(articleImageView),
            textStackFrame: frame(textContainer),
            titleFrame: frame(titleLabel),
            starFrame: frame(starImageView),
            metadataFrame: frame(metadataRow),
            unreadFrame: frame(unreadIndicator),
            feedIconFrame: frame(feedIconContainer),
            feedTitleFrame: frame(feedTitleLabel),
            commentsFrame: currentHasComments ? frame(commentsContainer) : nil,
            dateFrame: frame(dateLabel),
            publicationTimeIconFrame: currentShowsRelativePublicationTime ? frame(publicationTimeIconView) : nil,
            landscapeReadingTimeContainerFrame: currentReadingTime != nil
                ? frame(landscapeReadingTimeContainer)
                : nil,
            landscapeReadingTimeIconFrame: currentReadingTime != nil
                ? frame(landscapeReadingTimeIconView)
                : nil,
            landscapeReadingTimeFrame: currentReadingTime != nil
                ? frame(landscapeReadingTimeLabel)
                : nil,
            previewFrame: previewLabel.isHidden ? nil : frame(previewLabel),
            previewContinuationFrame: previewContinuationLabel.isHidden
                ? nil : frame(previewContinuationLabel)
        )
    }

    var portraitAspectConstraintDiagnosticsForTesting: (multiplier: CGFloat, constant: CGFloat, priority: UILayoutPriority, imageFrame: CGRect, contentBounds: CGRect, margins: NSDirectionalEdgeInsets, displayScale: CGFloat) {
        (portraitImageAspectConstraint.multiplier, portraitImageAspectConstraint.constant, portraitImageAspectConstraint.priority, articleImageView.frame, contentView.bounds, contentView.directionalLayoutMargins, traitCollection.displayScale)
    }
    var layoutVariantForTesting: IOSUIKitArticleCellLayoutVariant? { currentLayoutVariant }
    var feedIconImageForTesting: UIImage? { feedIconImageView.image }
    var feedTitlePresentationForTesting: (lineCount: Int, lineBreakMode: NSLineBreakMode) {
        (feedTitleLabel.numberOfLines, feedTitleLabel.lineBreakMode)
    }

    private func configureArticleImage(
        url: URL?,
        targetSize: CGSize,
        displayScale: CGFloat,
        articleChanged: Bool
    ) {
        guard let url, targetSize.width > 0, targetSize.height > 0 else {
            guard representedImageRequest != nil else { return }
            performanceMetrics?.recordImageBinding()
            invalidateImageBinding()
            representedImageRequest = nil
            articleImageView.image = nil
            imagePlaceholder.isHidden = false
            setArticleImagePresentation(loaded: false)
            return
        }

        let request = ArticleImageRequest(
            url: url,
            targetSize: targetSize,
            displayScale: displayScale,
            rasterScale: articleImageRasterScale(displayScale)
        )
        guard articleChanged || representedImageRequest != request else { return }
        performanceMetrics?.recordImageBinding()
        invalidateImageBinding()
        let bindingGeneration = imageBindingGeneration
        guard let articleID = representedArticleID else { return }
        representedImageRequest = request
        if let cachedImage = articleImagePipeline.cachedImage(for: request) {
            // Cache residency removes decode/raster work, but swapping several
            // distinct large rasters into visible cells in one display frame can
            // still hitch. Route warm-cache presentation through the same
            // frame-paced scheduler as cold async completions while scrolling.
            clearArticleImagePresentation()
            scheduleArticleImagePresentation(
                cachedImage,
                request: request,
                articleID: articleID,
                bindingGeneration: bindingGeneration,
                allowsAnimation: false
            )
            return
        }

        clearArticleImagePresentation()
        let pipeline = articleImagePipeline
        imageTask = Task { @MainActor [weak self, pipeline] in
            do {
                let loadedImage = try await pipeline.image(for: request, cacheWasChecked: true)
                guard !Task.isCancelled,
                      let self,
                      self.imageBindingGeneration == bindingGeneration,
                      self.representedArticleID == articleID,
                      self.representedImageRequest == request
                else { return }
                self.scheduleArticleImagePresentation(
                    loadedImage,
                    request: request,
                    articleID: articleID,
                    bindingGeneration: bindingGeneration,
                    allowsAnimation: true
                )
            } catch {
                guard !Task.isCancelled,
                      let self,
                      self.imageBindingGeneration == bindingGeneration,
                      self.representedArticleID == articleID,
                      self.representedImageRequest == request
                else { return }
                self.clearArticleImagePresentation()
            }
        }
    }

    private func scheduleArticleImagePresentation(
        _ image: CGImage,
        request: ArticleImageRequest,
        articleID: Int64,
        bindingGeneration: UInt64,
        allowsAnimation: Bool
    ) {
        IOSArticleImagePresentationScheduler.shared.enqueue(
            isStillValid: { [weak self] in
                guard let self else { return false }
                return self.imageBindingGeneration == bindingGeneration
                    && self.representedArticleID == articleID
                    && self.representedImageRequest == request
            },
            present: { [weak self] in
                guard let self else { return }
                self.presentArticleImage(
                    image,
                    animated: allowsAnimation && self.articleImageArrivalAnimationsEnabled
                )
            }
        )
    }

    private static let articleImageFadeDuration: CFTimeInterval = 0.2
    private static let articleImageFadeKey = "flux.articleImageFade"

    private func presentArticleImage(_ image: CGImage, animated: Bool) {
        if animated {
#if DEBUG
            articleImageFadeCountForTesting &+= 1
#endif
            let fade = CATransition()
            fade.type = .fade
            fade.duration = Self.articleImageFadeDuration
            articleImageView.layer.add(fade, forKey: Self.articleImageFadeKey)
        }
        // Use the physical display scale for UIImage semantics. Fixed
        // image-view constraints remain authoritative for the slot.
        articleImageView.image = UIImage(cgImage: image, scale: traitCollection.displayScale, orientation: .up)
        articleImageView.isOpaque = false
        imagePlaceholder.isHidden = true
        setArticleImagePresentation(loaded: true)
    }

    private func clearArticleImagePresentation() {
        articleImageView.layer.removeAnimation(forKey: Self.articleImageFadeKey)
        articleImageView.image = nil
        // The placeholder state has rounded corners of its own and must blend.
        articleImageView.isOpaque = false
        imagePlaceholder.isHidden = false
        setArticleImagePresentation(loaded: false)
    }

    private func setArticleImagePresentation(loaded: Bool) {
        articleImageView.contentMode = .scaleAspectFill
        articleImageView.clipsToBounds = loaded
        articleImageView.layer.cornerRadius = IOSUIKitArticleGeometry.articleImageCornerRadius
        articleImageView.backgroundColor = loaded ? .clear : .tertiarySystemFill
    }

    private func setFeedIconPresentation(loaded: Bool) {
        feedIconImageView.contentMode = loaded ? .scaleToFill : .scaleAspectFit
        // Core Animation resolves a rounded background analytically, but a
        // rounded mask over a sublayer needs an offscreen pass. The fallback
        // letter is centred inside the circle and never overflows it, so the
        // container keeps its rounded background without masking — matching the
        // cold article-image placeholder next to it.
        feedIconContainer.clipsToBounds = false
        feedIconContainer.layer.cornerRadius = loaded ? 0 : feedIconWidth.constant / 2
    }

    private func invalidateImageBinding() {
        imageBindingGeneration &+= 1
        imageTask?.cancel()
        imageTask = nil
    }

    private func updateAccessibility() {
        let reading = currentReadingTime.map { ", \(String(localized: "Reading time")) \($0)" } ?? ""
        accessibilityLabel = "\(currentTitle), \(currentFeedTitle), \(currentPublishedDate)\(reading), \(currentIsRead ? String(localized: "Read") : String(localized: "Unread"))\(currentIsStarred ? String(localized: ", starred") : "")"
        accessibilityValue = currentIsRead
            ? (currentIsStarred ? String(localized: "Read, starred") : String(localized: "Read"))
            : (currentIsStarred ? String(localized: "Unread, starred") : String(localized: "Unread"))
    }
}
