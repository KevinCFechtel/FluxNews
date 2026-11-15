import Foundation
import UserNotifications

final class SystemNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = SystemNotificationManager()

    private enum PayloadKey {
        static let candidateID = "flux.systemNotificationCandidateID"
        static let feedID = "flux.systemNotificationFeedID"
    }

    var onFeedSelected: ((Int64) -> Void)?

    func configure() { UNUserNotificationCenter.current().delegate = self }

    func ensureAuthorization() async throws {
        let center = UNUserNotificationCenter.current()
        switch (await center.notificationSettings()).authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return
        case .denied:
            throw SystemNotificationError.authorizationDenied
        case .notDetermined:
            guard try await center.requestAuthorization(options: [.alert]) else {
                throw SystemNotificationError.authorizationDenied
            }
        @unknown default:
            throw SystemNotificationError.authorizationDenied
        }
    }

    func deliver(
        _ candidates: [SystemNotificationCandidate],
        core: Flux,
        coordinator: AppleCoreSessionExecutionCoordinator
    ) async {
        for candidate in candidates {
            do {
                try await add(candidate)
                guard let acknowledgement = await coordinator.responsiveResult(
                    for: core,
                    { try core.acknowledgeSystemNotification(candidateId: candidate.candidateId) }
                ) else { return }
                if case let .failure(error) = acknowledgement { throw error }
            } catch {
                NativeLog.notification.error("system notification delivery failed candidate_id=\(candidate.candidateId, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func add(_ candidate: SystemNotificationCandidate) async throws {
        let content = UNMutableNotificationContent()
        content.title = candidate.feedTitle
        content.body = SystemNotificationPresentation.body(newCount: candidate.newCount, submittedAt: Date())
        content.userInfo = [PayloadKey.candidateID: candidate.candidateId, PayloadKey.feedID: candidate.feedId]
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "flux.system-notification.\(candidate.candidateId)", content: content, trigger: nil))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if let feedID = response.notification.request.content.userInfo[PayloadKey.feedID] as? Int64 {
            DispatchQueue.main.async { [weak self] in self?.onFeedSelected?(feedID) }
        } else if let number = response.notification.request.content.userInfo[PayloadKey.feedID] as? NSNumber {
            DispatchQueue.main.async { [weak self] in self?.onFeedSelected?(number.int64Value) }
        }
        completionHandler()
    }
}
