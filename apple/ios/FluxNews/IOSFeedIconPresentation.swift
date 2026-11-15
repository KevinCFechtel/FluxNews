import Foundation
import ImageIO
import Observation
import UIKit

struct IOSFeedIconKey: Hashable {
    let feedID: Int64
    let variant: FeedIconVariant
}

enum IOSFeedIconLoadState: Equatable {
    case idle
    case loading
    case available
    case unavailable
    case retryableFailure(retryAfter: TimeInterval)
}

@Observable final class IOSFeedIconPresentationState {
    var image: UIImage?
    private(set) var loadState: IOSFeedIconLoadState = .idle
    private(set) var revision: UInt64 = 0
#if DEBUG
    @ObservationIgnored private var testStateWaiters: [(IOSFeedIconLoadState, CheckedContinuation<Void, Never>)] = []
#endif

    func beginLoading() {
        loadState = .loading
        notifyTestStateWaiters()
    }

    func setAvailable(_ image: UIImage) {
        self.image = image
        loadState = .available
        revision &+= 1
        notifyTestStateWaiters()
    }

    func setUnavailable() {
        image = nil
        loadState = .unavailable
        revision &+= 1
        notifyTestStateWaiters()
    }

    func setRetryableFailure(retryAfter: TimeInterval) {
        image = nil
        loadState = .retryableFailure(retryAfter: retryAfter)
        revision &+= 1
        notifyTestStateWaiters()
    }

    func invalidateLoading() {
        guard loadState == .loading else { return }
        loadState = .idle
        notifyTestStateWaiters()
    }

    func canRequest(at time: TimeInterval) -> Bool {
        switch loadState {
        case .idle:
            true
        case let .retryableFailure(retryAfter):
            time >= retryAfter
        case .loading, .available, .unavailable:
            false
        }
    }

#if DEBUG
    func waitForLoadStateForTesting(_ expected: IOSFeedIconLoadState) async {
        guard loadState != expected else { return }
        await withCheckedContinuation { continuation in
            testStateWaiters.append((expected, continuation))
        }
    }

    private func notifyTestStateWaiters() {
        let matching = testStateWaiters.indices.reversed().filter { testStateWaiters[$0].0 == loadState }
        for index in matching {
            testStateWaiters.remove(at: index).1.resume()
        }
    }
#else
    private func notifyTestStateWaiters() {}
#endif
}

enum IOSFeedIconPresentation {
    static func variant(isDark: Bool) -> FeedIconVariant { isDark ? .dark : .normal }
}

struct IOSFeedIconRequestOwnership: Hashable {
    let key: IOSFeedIconKey
    let generation: UInt64
}

private enum IOSFeedIconImagePreparationError: Error {
    case invalidImageData
}

/// Feed icons are rendered in a fixed 22-point slot. Decode and rasterize the
/// Core PNG off-main after the bounded Core fetch and before presentation.
struct IOSPreparedFeedIcon: @unchecked Sendable {
    let image: UIImage
    let pixelSize: CGSize
}

enum IOSFeedIconImagePreparation {
    static let displaySidePoints: CGFloat = 22
    static let cornerRadius = displaySidePoints / 2

    static func prepare(data: Data, displayScale: CGFloat) throws -> IOSPreparedFeedIcon {
        let scale = max(displayScale, 1)
        let maxPixelDimension = max(1, Int((displaySidePoints * scale).rounded(.up)))
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw IOSFeedIconImagePreparationError.invalidImageData
        }
        let options: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            throw IOSFeedIconImagePreparationError.invalidImageData
        }
        let displayReady = renderDisplayReady(
            thumbnail,
            pixelSide: maxPixelDimension,
            cornerRadiusPixels: CGFloat(maxPixelDimension) / 2
        ) ?? thumbnail
        return .init(
            image: UIImage(cgImage: displayReady, scale: scale, orientation: .up),
            pixelSize: .init(width: displayReady.width, height: displayReady.height)
        )
    }

    private static func renderDisplayReady(
        _ image: CGImage,
        pixelSide: Int,
        cornerRadiusPixels: CGFloat
    ) -> CGImage? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: pixelSide,
            height: pixelSide,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: displayBitmapInfo
        ) else { return nil }
        context.interpolationQuality = .medium
        let destination = CGRect(x: 0, y: 0, width: pixelSide, height: pixelSide)
        context.clear(destination)
        let radius = min(cornerRadiusPixels, CGFloat(pixelSide) / 2)
        context.addPath(CGPath(roundedRect: destination, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        let scale = min(destination.width / CGFloat(image.width), destination.height / CGFloat(image.height))
        let drawSize = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        context.draw(
            image,
            in: .init(
                x: destination.midX - drawSize.width / 2,
                y: destination.midY - drawSize.height / 2,
                width: drawSize.width,
                height: drawSize.height
            )
        )
        return context.makeImage()
    }

    private static var displayBitmapInfo: UInt32 {
        CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
    }
}
