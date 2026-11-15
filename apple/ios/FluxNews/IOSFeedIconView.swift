import SwiftUI

struct FeedIconView: View {
    let feedID: Int64
    let title: String
    let state: IOSFeedIconPresentationState
    let onRequest: () -> Void
    var size: CGFloat = 22

    var body: some View {
        Group {
            if let image = state.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Text(title.prefix(1).uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Color.accentColor.gradient, in: Circle())
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task { onRequest() }
    }
}
