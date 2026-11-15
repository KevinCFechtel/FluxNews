import XCTest

final class BackupPasswordWorkflowTests: XCTestCase {
    func testImportFailureKeepsTheWorkflowAvailableForRetry() {
        var state = BackupPasswordSubmissionState()

        XCTAssertTrue(state.begin(isExport: false, password: "wrong", confirmation: ""))
        XCTAssertTrue(state.isProcessing)
        XCTAssertFalse(state.complete(error: "Backup could not be decrypted."))
        XCTAssertEqual(state.error, "Backup could not be decrypted.")
        XCTAssertFalse(state.isProcessing)
        XCTAssertTrue(state.begin(isExport: false, password: "correct", confirmation: ""))
    }

    func testSuccessCompletesTheWorkflow() {
        var state = BackupPasswordSubmissionState()

        XCTAssertTrue(state.begin(isExport: false, password: "password", confirmation: ""))
        XCTAssertTrue(state.complete(error: nil))
        XCTAssertFalse(state.isProcessing)
        XCTAssertNil(state.error)
    }

    func testSynchronizedImportRequestsConciseSuccessConfirmation() {
        XCTAssertEqual(BackupImportOutcome.synchronized.confirmationKey, "Backup imported successfully.")
    }

    func testImportWithSyncFailureRequestsSuccessWarningInsteadOfSheetError() {
        var state = BackupPasswordSubmissionState()

        XCTAssertTrue(state.begin(isExport: false, password: "password", confirmation: ""))
        XCTAssertTrue(state.complete(error: nil))
        XCTAssertNil(state.error)
        XCTAssertEqual(
            BackupImportOutcome.synchronizationFailed.confirmationKey,
            "Backup imported successfully. Synchronization could not be completed and will be retried later."
        )
    }

    func testExportValidationAndDuplicateSubmissionStayLocal() {
        var state = BackupPasswordSubmissionState()

        XCTAssertFalse(state.begin(isExport: true, password: "", confirmation: ""))
        XCTAssertEqual(state.error, String(localized: "Enter a backup password."))
        XCTAssertFalse(state.begin(isExport: true, password: "one", confirmation: "two"))
        XCTAssertEqual(state.error, String(localized: "The passwords do not match."))
        XCTAssertTrue(state.begin(isExport: true, password: "one", confirmation: "one"))
        XCTAssertFalse(state.begin(isExport: true, password: "one", confirmation: "one"))
        XCTAssertFalse(state.complete(error: "The backup could not be written."))
        XCTAssertEqual(state.error, "The backup could not be written.")
    }
}
