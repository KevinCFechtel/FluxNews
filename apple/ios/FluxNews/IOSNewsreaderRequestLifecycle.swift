import Foundation

struct IOSNewsreaderReadRequest: Equatable {
    let session: UInt64
    let generation: UInt64
    let selectionCountGeneration: UInt64
    let errorGeneration: UInt64
}

struct IOSNewsreaderTimelinePageRequest: Equatable {
    let session: UInt64
    let timelineGeneration: UInt64
    let requestGeneration: UInt64
}

struct IOSNewsreaderReadLifecycle {
    private(set) var session: UInt64 = 0
    private(set) var articleGeneration: UInt64 = 0
    private(set) var navigationGeneration: UInt64 = 0
    private(set) var selectionCountGeneration: UInt64 = 0
    private(set) var errorGeneration: UInt64 = 0
    private(set) var timelineGeneration: UInt64 = 0
    private(set) var timelinePageRequestGeneration: UInt64 = 0

    mutating func invalidateSession() {
        session &+= 1
        articleGeneration &+= 1
        navigationGeneration &+= 1
        selectionCountGeneration &+= 1
        errorGeneration &+= 1
        timelineGeneration &+= 1
    }

    mutating func beginArticle() -> IOSNewsreaderReadRequest {
        articleGeneration &+= 1
        selectionCountGeneration &+= 1
        errorGeneration &+= 1
        timelineGeneration &+= 1
        return .init(session: session, generation: articleGeneration, selectionCountGeneration: selectionCountGeneration, errorGeneration: errorGeneration)
    }

    mutating func beginNextArticlePage() -> IOSNewsreaderTimelinePageRequest {
        timelinePageRequestGeneration &+= 1
        return .init(session: session, timelineGeneration: timelineGeneration, requestGeneration: timelinePageRequestGeneration)
    }

    mutating func invalidateArticle() {
        articleGeneration &+= 1
        selectionCountGeneration &+= 1
        errorGeneration &+= 1
        timelineGeneration &+= 1
    }

    mutating func invalidateNavigation() {
        navigationGeneration &+= 1
        errorGeneration &+= 1
    }

    mutating func beginNavigation() -> IOSNewsreaderReadRequest {
        navigationGeneration &+= 1
        errorGeneration &+= 1
        return .init(session: session, generation: navigationGeneration, selectionCountGeneration: selectionCountGeneration, errorGeneration: errorGeneration)
    }

    mutating func beginSelectionCount() -> IOSNewsreaderReadRequest {
        selectionCountGeneration &+= 1
        errorGeneration &+= 1
        return .init(session: session, generation: selectionCountGeneration, selectionCountGeneration: selectionCountGeneration, errorGeneration: errorGeneration)
    }

    func isCurrentArticle(_ request: IOSNewsreaderReadRequest) -> Bool { request.session == session && request.generation == articleGeneration }
    func isCurrentNavigation(_ request: IOSNewsreaderReadRequest) -> Bool { request.session == session && request.generation == navigationGeneration }
    func isCurrentSelectionCount(_ request: IOSNewsreaderReadRequest) -> Bool { request.session == session && request.selectionCountGeneration == selectionCountGeneration }
    func ownsTimelinePage(_ request: IOSNewsreaderTimelinePageRequest) -> Bool { request.session == session && request.timelineGeneration == timelineGeneration }
    func ownsError(_ request: IOSNewsreaderReadRequest) -> Bool { request.errorGeneration == errorGeneration }
}


enum IOSManualSyncState: Equatable {
    case idle
    case running
    case cancelling

    var isActive: Bool { self != .idle }
}

struct IOSManualSyncRequest: Hashable {
    let session: UInt64
    let generation: UInt64
}

struct IOSManualSyncLifecycle {
    private(set) var session: UInt64 = 0
    private(set) var generation: UInt64 = 0
    private(set) var state: IOSManualSyncState = .idle

    mutating func begin() -> IOSManualSyncRequest? {
        guard state == .idle else { return nil }
        generation &+= 1
        state = .running
        return .init(session: session, generation: generation)
    }

    mutating func requestCancellation(_ request: IOSManualSyncRequest) -> Bool {
        guard isCurrent(request), state == .running else { return false }
        state = .cancelling
        return true
    }

    mutating func supersedeCancelled(_ request: IOSManualSyncRequest) -> Bool {
        guard isCurrent(request), state == .cancelling else { return false }
        generation &+= 1
        state = .idle
        return true
    }

    mutating func finish(_ request: IOSManualSyncRequest) -> Bool {
        guard isCurrent(request) else { return false }
        state = .idle
        return true
    }

    mutating func invalidateSession() {
        session &+= 1
        generation &+= 1
        state = .idle
    }

    func isCurrent(_ request: IOSManualSyncRequest) -> Bool {
        request.session == session && request.generation == generation
    }

    func canPublishCompletion(_ request: IOSManualSyncRequest) -> Bool {
        isCurrent(request) && state == .running
    }
}

enum IOSSyncCountRefreshPolicy: Equatable {
    case none
    case allCounts
    case navigationAndAllCounts

    static func resolve(dataChanged: Bool, navigationChanged: Bool) -> Self {
        if navigationChanged { return .navigationAndAllCounts }
        return dataChanged ? .allCounts : .none
    }
}

enum IOSScrolloverPresentationPhase: Equatable {
    case interacting
    case decelerating
    case idle

    var isScrolling: Bool { self != .idle }
}

enum IOSNewsreaderEventRoutingPolicy {
    static func shouldDispatchSyncCompleted(reason: SyncReason?) -> Bool {
        guard let reason else { return false }
        return reason != .manual
    }
}
