import Foundation
import UserNotifications

enum IOSSystemNotificationAuthorizationStatus: Equatable {
    case notDetermined
    case authorized
    case provisional
    case ephemeral
    case denied
}

struct IOSSystemNotificationRequest: Equatable {
    let identifier: String
    let title: String
    let body: String
    let candidateID: Int64
    let feedID: Int64
}

@MainActor
protocol IOSSystemNotificationCenter: AnyObject {
    func authorizationStatus() async -> IOSSystemNotificationAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func add(_ request: IOSSystemNotificationRequest) async throws
}

@MainActor
final class IOSUserNotificationCenterAdapter: IOSSystemNotificationCenter {
    static let shared = IOSUserNotificationCenterAdapter()

    func authorizationStatus() async -> IOSSystemNotificationAuthorizationStatus {
        switch (await UNUserNotificationCenter.current().notificationSettings()).authorizationStatus {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .authorized:
            .authorized
        case .provisional:
            .provisional
        case .ephemeral:
            .ephemeral
        @unknown default:
            .denied
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
    }

    func add(_ request: IOSSystemNotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.userInfo = [
            IOSSystemNotificationManager.PayloadKey.candidateID: request.candidateID,
            IOSSystemNotificationManager.PayloadKey.feedID: request.feedID,
        ]
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: request.identifier,
                content: content,
                trigger: nil
            )
        )
    }
}

enum IOSSystemNotificationError: LocalizedError {
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            String(localized: "FluxNews notification permission is disabled. Enable notifications in iOS Settings to use System Notifications.")
        }
    }
}

@MainActor
final class IOSSystemNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = IOSSystemNotificationManager()

    enum PayloadKey {
        static let candidateID = "flux.systemNotificationCandidateID"
        static let feedID = "flux.systemNotificationFeedID"
    }

    private let center: IOSSystemNotificationCenter
    private let logger = IOSAppLogger(category: "notification")
    private var pendingFeedID: Int64?

    var onFeedSelected: ((Int64) -> Void)? {
        didSet {
            guard let onFeedSelected, let pendingFeedID else { return }
            self.pendingFeedID = nil
            onFeedSelected(pendingFeedID)
        }
    }

    init(center: IOSSystemNotificationCenter? = nil) {
        self.center = center ?? IOSUserNotificationCenterAdapter.shared
        super.init()
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    func ensureAuthorization() async throws {
        switch await center.authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            return
        case .denied:
            throw IOSSystemNotificationError.authorizationDenied
        case .notDetermined:
            guard try await center.requestAuthorization() else {
                throw IOSSystemNotificationError.authorizationDenied
            }
        }
    }

    func deliver(
        _ candidates: [SystemNotificationCandidate],
        acknowledge: @escaping @MainActor (Int64) async -> Bool
    ) async {
        for candidate in candidates {
            do {
                try await center.add(
                    IOSSystemNotificationRequest(
                        identifier: "flux.system-notification.\(candidate.candidateId)",
                        title: candidate.feedTitle,
                        body: SystemNotificationPresentation.body(
                            newCount: candidate.newCount,
                            submittedAt: Date()
                        ),
                        candidateID: candidate.candidateId,
                        feedID: candidate.feedId
                    )
                )
                guard await acknowledge(candidate.candidateId) else {
                    logger.error(
                        "system notification ACK failed candidate_id=\(candidate.candidateId)"
                    )
                    continue
                }
            } catch {
                logger.error(
                    "system notification delivery failed candidate_id=\(candidate.candidateId) error=\(String(reflecting: error))"
                )
            }
        }
    }

    func route(feedID: Int64) {
        if let onFeedSelected {
            onFeedSelected(feedID)
        } else {
            pendingFeedID = feedID
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let value = response.notification.request.content.userInfo[PayloadKey.feedID]
        let feedID: Int64?
        if let value = value as? Int64 {
            feedID = value
        } else if let number = value as? NSNumber {
            feedID = number.int64Value
        } else {
            feedID = nil
        }
        if let feedID {
            Task { @MainActor [weak self] in
                self?.route(feedID: feedID)
            }
        }
        completionHandler()
    }
}
