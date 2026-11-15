struct ReaderRequestState {
    private(set) var latest: UInt64 = 0

    mutating func begin() -> UInt64 {
        latest &+= 1
        return latest
    }

    func isCurrent(_ request: UInt64) -> Bool { request == latest }
}
