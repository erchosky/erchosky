import XCTest
import BrisaCore
@testable import BrisaApp

final class FinalCheckTests: XCTestCase {
    @MainActor
    private func withState(_ body: (AppState) async throws -> Void) async throws {
        let sandbox = URL(fileURLWithPath: try Paths.systemLocation(NSTemporaryDirectory()))
            .appendingPathComponent("BrisaFinal-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let suite = "dev.brisa.final." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let previousLanguage = L10n.currentPreference
        defer { L10n.setPreference(previousLanguage) }
        let state = AppState(userDefaults: defaults, storeURL: sandbox.appendingPathComponent("State"),
                             homeDirectory: sandbox.path, startServices: false)
        defer { state.shutdown() }
        try await body(state)
    }

    @MainActor
    func testQueuedQuitDoesNotShutDownNewScanOrOperation() async throws {
        try await withState { state in
            _ = try await state.handle(IPCRequest(command: "quit"))
            // Another request can start a task during the response's 0.5-second delivery grace period.
            state.scanning = true
            state.operating = true
            try await Task.sleep(nanoseconds: 700_000_000)
            XCTAssertTrue(state.scanning)
            XCTAssertTrue(state.operating)
            XCTAssertNotNil(state.lastError)
        }
    }

    @MainActor
    func testShutdownDiscardsPendingScanCompletion() async throws {
        try await withState { state in
            try state.startScan()
            state.shutdown()
            // The detached scan must finish before the sandbox goes away, without publishing its result.
            try await Task.sleep(nanoseconds: 300_000_000)
            XCTAssertFalse(state.scanning)
            XCTAssertNil(state.scan.finishedAt)
            XCTAssertEqual(state.contextualScanStatus, "pending")
            XCTAssertFalse(state.activity.contains { $0.message.contains("0/11") })
        }
    }

    @MainActor
    func testLibraryLocationFilterUsesConfiguredHome() async throws {
        try await withState { state in
            var scan = ScanResult()
            let path = state.homePath + "/Library/Caches/example.cache"
            scan.files = [IndexedFile(id: "example", path: path, root: state.homePath + "/Library/Caches",
                identity: FileIdentity(device: 1, inode: 2, size: 10, modified: 1, changed: 1),
                allocatedBytes: 10, category: .cache, modifiedAt: Date(), eligible: false,
                reason: "inventory_only", confidence: "inventory")]
            state.scan = scan
            state.locationFilter = "library"
            XCTAssertEqual(state.filteredFiles.map(\.id), ["example"])
        }
    }

    @MainActor
    func testFreeSpaceLabelKeepsPollingWithClosedWindowAndStopsWhenDisabled() async throws {
        try await withState { state in
            let metrics = state.liveMetrics
            XCTAssertFalse(metrics.isStatusBarPollingActive)
            state.showMenuBarFreeSpace = true
            XCTAssertTrue(metrics.isStatusBarPollingActive)
            XCTAssertFalse(metrics.isWindowPollingActive)
            XCTAssertFalse(metrics.isBreakdownPollingActive)

            metrics.setMenuVisible(true)
            XCTAssertFalse(metrics.isStatusBarPollingActive, "Open popover already refreshes the shared metrics")
            XCTAssertTrue(metrics.isBreakdownPollingActive)
            metrics.setMenuVisible(false)
            XCTAssertTrue(metrics.isStatusBarPollingActive)

            state.showMenuBarFreeSpace = false
            XCTAssertFalse(metrics.isStatusBarPollingActive)
            state.showMenuBarFreeSpace = true
            state.shutdown()
            XCTAssertFalse(metrics.isStatusBarPollingActive)
        }
    }
}
