import Foundation

enum BackupImportOutcome: Equatable {
    case synchronized
    case synchronizationFailed

    var confirmationKey: String {
        switch self {
        case .synchronized:
            "Backup imported successfully."
        case .synchronizationFailed:
            "Backup imported successfully. Synchronization could not be completed and will be retried later."
        }
    }

    var confirmationMessage: String { String(localized: String.LocalizationValue(confirmationKey)) }
}

enum BackupPasswordSubmissionResult {
    case success(String? = nil)
    case failure(String)
}

struct BackupPasswordSubmissionState: Equatable {
    private(set) var isProcessing = false
    private(set) var error: String?

    mutating func begin(isExport: Bool, password: String, confirmation: String) -> Bool {
        guard !isProcessing else { return false }
        guard !password.isEmpty else {
            error = String(localized: "Enter a backup password.")
            return false
        }
        guard !isExport || password == confirmation else {
            error = String(localized: "The passwords do not match.")
            return false
        }
        error = nil
        isProcessing = true
        return true
    }

    mutating func complete(error: String?) -> Bool {
        isProcessing = false
        self.error = error
        return error == nil
    }

    mutating func clearError() {
        guard !isProcessing else { return }
        error = nil
    }
}
