struct StartupRouteState {
    private(set) var hasExplicitRoute = false

    mutating func markExplicitRoute() {
        hasExplicitRoute = true
    }

    var shouldApplyStartupScope: Bool {
        !hasExplicitRoute
    }
}
