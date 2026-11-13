import XCTest
import AppKit
@testable import BrisaCore
@testable import BrisaApp

private final class RegressionTrashMover: TrashMoving, @unchecked Sendable {
    private let lock = NSLock()
    private let trashDir: URL
    private(set) var movedPaths: [String] = []

    init(trashDir: URL) {
        self.trashDir = trashDir
        try? FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
    }

    func move(_ url: URL) throws -> URL? {
        let dest = trashDir.appendingPathComponent(url.lastPathComponent + "-" + UUID().uuidString.prefix(6))
        try FileManager.default.moveItem(at: url, to: dest)
        lock.lock()
        movedPaths.append(url.path)
        lock.unlock()
        return dest
    }
}

private final class SlowRecheckExecutor: CommandExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var inspectCalls = 0
    let delayUs: useconds_t

    init(delayMs: Int = 110) {
        self.delayUs = useconds_t(delayMs * 1000)
    }

    func run(_ request: CommandExecutionRequest, control: ScanControl?) throws -> CommandResult {
        usleep(delayUs)
        if request.arguments.contains("--version") {
            lock.lock()
            inspectCalls += 1
            lock.unlock()
            return CommandResult(status: 0, output: "10.8.2\n", error: "", timedOut: false)
        }
        if request.arguments == ["config", "get", "cache"] {
            return CommandResult(status: 0, output: "/nonexistent/npm-cache\n", error: "", timedOut: false)
        }
        return CommandResult(status: 0, output: "", error: "", timedOut: false)
    }
}

final class StabilityAndPerformanceRegressionTests: XCTestCase {
    @MainActor
    private func makeTestEnvironment() throws -> (sandbox: URL, state: AppState, trash: RegressionTrashMover, executor: SlowRecheckExecutor, suite: String) {
        let base = try Paths.systemLocation(NSTemporaryDirectory())
        let sandbox = URL(fileURLWithPath: base)
            .appendingPathComponent("BrisaStability-\(UUID().uuidString.prefix(10))", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)

        let cacheRoot = sandbox.appendingPathComponent("Library/Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let storeDir = sandbox.appendingPathComponent("State", isDirectory: true)
        let trash = RegressionTrashMover(trashDir: sandbox.appendingPathComponent(".FakeTrash", isDirectory: true))
        let executor = SlowRecheckExecutor(delayMs: 110)
        let suite = "dev.brisa.stability.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))

        let state = AppState(
            userDefaults: defaults,
            storeURL: storeDir,
            ipcSocketPath: nil,
            homeDirectory: sandbox.path,
            startServices: false,
            commandExecutor: executor,
            trashMover: trash
        )
        return (sandbox, state, trash, executor, suite)
    }

    private func statIdentity(at url: URL, modifiedAt: Date) throws -> FileIdentity {
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)
        var st = stat()
        guard lstat(url.path, &st) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return SafetyPolicy.identity(st)
    }

    @MainActor
    func testMenuExploreAndCategorySelectionAllowsReviewAndCleanDismissalCleansPendingPlan() async throws {
        let (sandbox, state, trash, _, suite) = try makeTestEnvironment()
        defer {
            state.shutdown()
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: sandbox)
        }

        let cacheRoot = sandbox.appendingPathComponent("Library/Caches/SampleApp", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let itemURL = cacheRoot.appendingPathComponent("old.cache")
        try Data(repeating: 1, count: 4096).write(to: itemURL)
        let oldDate = Date().addingTimeInterval(-30 * 86400)
        let identity = try statIdentity(at: itemURL, modifiedAt: oldDate)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: cacheRoot.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: sandbox.appendingPathComponent("Library/Caches").path)

        let indexed = IndexedFile(
            id: "old-cache",
            path: itemURL.path,
            root: sandbox.appendingPathComponent("Library/Caches").path,
            identity: identity,
            allocatedBytes: 4096,
            category: .cache,
            modifiedAt: oldDate,
            eligible: true,
            reason: "eligible",
            confidence: "high",
            storageCategory: .appCaches,
            titleES: "Cache Old",
            titleEN: "Old Cache",
            logicalBytes: 4096
        )

        var scan = ScanResult()
        scan.files = [indexed]
        scan.finishedAt = Date()
        scan.complete = true
        scan.rebuildCategoryAggregates()
        state.scan = scan
        state.syncScanAggregates()

        // Navigate into Explore -> Category and select an eligible file inside the category route
        state.tools.pushMenuRoute(.exploreSpace)
        state.tools.pushMenuRoute(.category(.appCaches))
        state.toggle(indexed)
        XCTAssertEqual(state.selected, [indexed.id])

        // Performing review from category selection must open the review plan directly without trapping
        MenuPanelLiveBridge.performReviewAction(state: state, tools: state.tools)
        XCTAssertEqual(state.tools.menuRoute, .reviewPlan)
        XCTAssertNotNil(state.tools.pendingPlanContext)

        // Popping back from .reviewPlan cleans pending plan context without executing
        state.tools.popMenuRoute()
        XCTAssertEqual(state.tools.menuRoute, .category(.appCaches))
        XCTAssertNil(state.tools.pendingPlanContext)
        XCTAssertTrue(trash.movedPaths.isEmpty)

        // Review again, execute to Trash (sandbox mock), then pop from .executionResult and verify cleanup
        MenuPanelLiveBridge.performReviewAction(state: state, tools: state.tools)
        XCTAssertEqual(state.tools.menuRoute, .reviewPlan)
        state.tools.executePendingPlan()
        for _ in 0..<40 where state.tools.isExecutingPlan {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertEqual(state.tools.menuRoute, .executionResult)
        let report = try XCTUnwrap(state.tools.lastExecutionReport)
        XCTAssertEqual(report.outcome, .completed, "\(report.summaryEN) errors=\(report.journalEntries.compactMap(\.error))")
        XCTAssertEqual(trash.movedPaths, [itemURL.path])

        state.tools.popMenuRoute()
        XCTAssertNil(state.tools.lastExecutionReport)
        XCTAssertNil(state.tools.pendingPlanContext)
    }

    @MainActor
    func testAddProtectionPreservesCompletedScanInventoryAndUpdatesProtectedItemsInPlace() throws {
        let (sandbox, state, _, _, suite) = try makeTestEnvironment()
        defer {
            state.shutdown()
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: sandbox)
        }

        let protectedDir = sandbox.appendingPathComponent("Library/Caches/ProtectedApp", isDirectory: true)
        let otherDir = sandbox.appendingPathComponent("Library/Caches/OtherApp", isDirectory: true)
        try FileManager.default.createDirectory(at: protectedDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherDir, withIntermediateDirectories: true)
        let f1URL = protectedDir.appendingPathComponent("nested.cache")
        let f2URL = otherDir.appendingPathComponent("keep.cache")
        try Data(repeating: 2, count: 4096).write(to: f1URL)
        try Data(repeating: 3, count: 4096).write(to: f2URL)

        let oldDate = Date().addingTimeInterval(-30 * 86400)
        let id1 = try statIdentity(at: f1URL, modifiedAt: oldDate)
        let id2 = try statIdentity(at: f2URL, modifiedAt: oldDate)

        let f1 = IndexedFile(
            id: "p1", path: f1URL.path, root: sandbox.appendingPathComponent("Library/Caches").path,
            identity: id1, allocatedBytes: 4096, category: .cache, modifiedAt: oldDate,
            eligible: true, reason: "eligible", confidence: "high", storageCategory: .appCaches,
            titleES: "Nested", titleEN: "Nested", logicalBytes: 4096
        )
        let f2 = IndexedFile(
            id: "p2", path: f2URL.path, root: sandbox.appendingPathComponent("Library/Caches").path,
            identity: id2, allocatedBytes: 4096, category: .cache, modifiedAt: oldDate,
            eligible: true, reason: "eligible", confidence: "high", storageCategory: .appCaches,
            titleES: "Other", titleEN: "Other", logicalBytes: 4096
        )

        var scan = ScanResult()
        scan.files = [f1, f2]
        scan.finishedAt = Date()
        scan.complete = true
        scan.rebuildCategoryAggregates()
        state.scan = scan
        state.syncScanAggregates()
        try state.setSelection([f1.id, f2.id])

        try state.addProtection(protectedDir.path)

        // Completed inventory must remain present while protected descendants become locked and unselected
        XCTAssertNotNil(state.scan.finishedAt)
        XCTAssertEqual(state.scan.files.count, 2)
        XCTAssertEqual(state.selected, [f2.id])
        XCTAssertEqual(state.eligibleFiles.map(\.id), [f2.id])
        XCTAssertEqual(state.sortedEligibleFiles.map(\.id), [f2.id])

        let updatedF1 = try XCTUnwrap(state.scan.files.first(where: { $0.id == f1.id }))
        XCTAssertFalse(updatedF1.isReviewable)
        XCTAssertTrue(updatedF1.inventoryOnly)
        XCTAssertEqual(updatedF1.cleanupEligibility, .lockedProtectedScope)
        XCTAssertTrue(state.preferences.protectedPaths.contains(Paths.normalized(protectedDir.path)))
    }

    @MainActor
    func testRapidInspectApplicationSwitchingCommitsLatestAndDiscardsStale() async throws {
        let (sandbox, state, _, _, suite) = try makeTestEnvironment()
        defer {
            state.shutdown()
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: sandbox)
        }

        func makeApp(_ name: String, bundleID: String) throws -> ApplicationItem {
            let url = sandbox.appendingPathComponent("Applications/\(name).app", isDirectory: true)
            let contents = url.appendingPathComponent("Contents", isDirectory: true)
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleName": name]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"))
            return ApplicationItem(url: url)
        }

        let app1 = try makeApp("FirstApp", bundleID: "com.example.first")
        let app2 = try makeApp("SecondApp", bundleID: "com.example.second")
        state.applications = [app1, app2]

        state.tools.inspectApplication(app1)
        state.tools.inspectApplication(app2)

        for _ in 0..<60 where state.tools.isInspectingApp {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertFalse(state.tools.isInspectingApp)
        XCTAssertEqual(state.tools.selectedAppID, app2.id)
        XCTAssertEqual(state.tools.inspectedApp?.app.bundlePath, app2.url.path)
    }

    @MainActor
    func testRecheckPendingPlanRunsOffMainActorAndDiscardsCancelledRecheck() async throws {
        let (sandbox, state, _, _, suite) = try makeTestEnvironment()
        defer {
            state.shutdown()
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: sandbox)
        }

        let npmBin = sandbox.appendingPathComponent(".local/bin/npm")
        try FileManager.default.createDirectory(at: npmBin.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\nexit 0\n".write(to: npmBin, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: npmBin.path)

        let cap = PackageManagerOperationCapability(
            id: "npm.cache.clean",
            kind: .npm,
            titleES: "Limpiar npm",
            titleEN: "Clean npm",
            descriptionES: "npm",
            descriptionEN: "npm",
            commandPreview: "npm cache clean --force",
            executable: npmBin.path,
            arguments: ["cache", "clean", "--force"],
            scope: .entireCache,
            measuredCacheBytes: 4096,
            estimatedReclaimableBytes: 4096,
            sizeBasis: .measured,
            preservedSummaryES: "ok",
            preservedSummaryEN: "ok",
            regenerationES: "ok",
            regenerationEN: "ok",
            isAvailable: true
        )
        let insp = PackageManagerInspection(
            kind: .npm,
            executablePath: npmBin.path,
            versionString: "10.8.0",
            majorVersion: 10,
            isInstalled: true,
            cachePaths: [sandbox.path],
            cacheAllocatedBytes: 4096,
            cacheLogicalBytes: 4096,
            installedPackagesPaths: [],
            preservedSummaryES: "ok",
            preservedSummaryEN: "ok",
            capabilities: [cap]
        )

        state.tools.preparePackageManagerPlan(inspection: insp, capability: cap, fromMenuBar: true)
        let t0 = DispatchTime.now().uptimeNanoseconds
        state.tools.recheckPendingPlan()
        let callElapsedMs = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000.0

        // Must yield control immediately instead of blocking MainActor for the 110ms command latency
        XCTAssertLessThan(callElapsedMs, 35.0)
        XCTAssertTrue(state.tools.isRecheckingPlan)

        for _ in 0..<60 where state.tools.isRecheckingPlan {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertFalse(state.tools.isRecheckingPlan)
        XCTAssertNotNil(state.tools.pendingPlanContext)

        // Start a second recheck and cancel/dismiss before it finishes; stale result must not reopen plan
        state.tools.recheckPendingPlan()
        XCTAssertTrue(state.tools.isRecheckingPlan)
        state.tools.dismissPlanReview()
        try await Task.sleep(nanoseconds: 180_000_000)
        XCTAssertNil(state.tools.pendingPlanContext)
        XCTAssertFalse(state.tools.isRecheckingPlan)
    }

    @MainActor
    func testQuitProtectionHonorsToolsActiveWorkAndBreakdownDemandControlsPolling() async throws {
        let (sandbox, state, _, _, suite) = try makeTestEnvironment()
        defer {
            state.shutdown()
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: sandbox)
        }

        state.tools.isScanningPackages = true
        XCTAssertTrue(state.hasActiveWork)
        let busySnap = MenuPanelSnapshot(
            computerName: state.computerName,
            categories: state.categories,
            fileCount: 0,
            allocatedBytes: 0,
            eligibleBytes: 0,
            finishedAt: nil,
            complete: false,
            isStale: false,
            scanning: false,
            operating: false,
            toolsBusy: state.tools.hasActiveWork,
            selectedCount: 1,
            completedCategories: 0
        )
        XCTAssertTrue(busySnap.hasActiveWork)
        do {
            _ = try await state.handle(IPCRequest(command: "quit"))
            XCTFail("Expected quit to reject while tools scan is active")
        } catch BrisaError.rejected {
            // Expected
        }
        state.tools.isScanningPackages = false
        XCTAssertFalse(state.hasActiveWork)

        let metrics = LiveMetricsStore(observeLifecycle: false)
        defer { metrics.shutdown() }
        metrics.setMenuVisible(true, breakdownNeeded: false)
        XCTAssertTrue(metrics.isMenuVisible)
        XCTAssertFalse(metrics.isBreakdownPollingActive)
        XCTAssertTrue(metrics.isWindowPollingActive)

        metrics.setMenuBreakdownNeeded(true)
        XCTAssertTrue(metrics.isBreakdownPollingActive)
        XCTAssertFalse(metrics.isWindowPollingActive)

        metrics.setMenuVisible(false)
        XCTAssertFalse(metrics.isBreakdownPollingActive)
        XCTAssertFalse(metrics.isWindowPollingActive)
    }
}
