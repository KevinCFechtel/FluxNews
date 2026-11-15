import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct AudioPlaybackActivityAttributes: ActivityAttributes {
    public typealias AudioPlaybackState = ContentState

    struct ContentState: Codable, Hashable {
        let itemTitle: String
        let feedTitle: String
        let isPlaying: Bool
        let currentPosition: Int // in seconds
        let duration: Int // in seconds
        let artworkUrl: String?
    }

    let activityIdentifier: String
}
