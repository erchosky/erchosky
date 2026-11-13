import XCTest
import BrisaCore
@testable import BrisaApp

final class LifecycleAndOptimizationTests: XCTestCase {
    @MainActor
    func testLiveMetricsStoreIdleLifecycleAndRapidMenuToggleDoNotLeakTimers() {
        let store = LiveMetricsStore(observeLifecycle: false)
        defer { store.shutdown() }

        XCTAssertFalse(store.isMenuVisible)
        XCTAssertFalse(store.isWindowPollingActive)
        XCTAssertFalse(store.isBreakdownPollingActive)

        let tokenA = UUID()
        let tokenB = UUID()
        for _ in 0..<20 {
            store.setMenuVisible(true, token: tokenA)
            XCTAssertTrue(store.isMenuVisible)
            XCTAssertTrue(store.isBreakdownPollingActive)
            store.setMenuVisible(false, token: tokenA)
        }
        XCTAssertFalse(store.isMenuVisible)
        XCTAssertFalse(store.isWindowPollingActive)
        XCTAssertFalse(store.isBreakdownPollingActive)

        store.setMenuVisible(true, token: tokenA)
        store.setMenuVisible(true, token: tokenB)
        store.setMenuVisible(false, token: tokenA)
        XCTAssertTrue(store.isMenuVisible, "Closing one menu observer must keep visibility until all close")
        XCTAssertTrue(store.isBreakdownPollingActive)
        store.setMenuVisible(false, token: tokenB)
        XCTAssertFalse(store.isMenuVisible)
        XCTAssertFalse(store.isBreakdownPollingActive)

        store.shutdown()
        store.setMenuVisible(true, token: tokenA)
        store.setWindowVisible(true, token: tokenB)
        XCTAssertFalse(store.isMenuVisible)
        XCTAssertFalse(store.isWindowPollingActive)
        XCTAssertFalse(store.isBreakdownPollingActive)
    }

    @MainActor
    func testLiveMetricsStoreForcedSampleDoesNotReuseNonForcedInFlight() async {
        let store = LiveMetricsStore(observeLifecycle: false)
        defer { store.shutdown() }

        async let nonForced = store.sample(maxAge: 0, forceSnapshots: false)
        async let forced = store.sample(maxAge: 0, forceSnapshots: true)

        let (first, second) = await (nonForced, forced)
        XCTAssertGreaterThanOrEqual(second.date, first.date)
        XCTAssertNotNil(store.snapshot)
    }

    @MainActor
    func testLiveMetricsStoreLateBreakdownDiscardedAfterMenuCloses() async {
        let store = LiveMetricsStore(observeLifecycle: false)
        defer { store.shutdown() }

        let token = UUID()
        store.setMenuVisible(true, token: token)
        let pending = Task { @MainActor in
            await store.sampleBreakdown()
        }
        await Task.yield()
        store.setMenuVisible(false, token: token)
        _ = await pending.value

        XCTAssertNil(store.breakdown, "Late breakdown completions must be ignored once menu closes")
        XCTAssertFalse(store.isBreakdownPollingActive)
    }

    @MainActor
    func testAppStateIsolationLanguageSwitchScenario10IPCAndFilterConsistency() async throws {
        let sandbox = URL(fileURLWithPath: try Paths.systemLocation(NSTemporaryDirectory()))
            .appendingPathComponent("BrisaAppOpt-" + UUID().uuidString.prefix(12), isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let suiteName = "dev.brisa.test." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storeDir = sandbox.appendingPathComponent("Store", isDirectory: true)
        let cacheRoot = sandbox.appendingPathComponent("Library/Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let sentinel = cacheRoot.appendingPathComponent("keep.txt")
        try Data("intact".utf8).write(to: sentinel)

        let state = AppState(
            userDefaults: defaults,
            storeURL: storeDir,
            ipcSocketPath: nil,
            homeDirectory: sandbox.path,
            startServices: false
        )
        defer { state.shutdown() }

        let now = Date()
        let f1 = IndexedFile(
            id: "alpha", path: cacheRoot.appendingPathComponent("AlphaCache/item").path, root: cacheRoot.path,
            identity: FileIdentity(device: 1, inode: 100, size: 4096, modified: 1, changed: 1),
            allocatedBytes: 4096, category: .cache, modifiedAt: now, eligible: true, reason: "eligible", confidence: "high",
            storageCategory: .appCaches, titleES: "Cache Alpha", titleEN: "Alpha Cache", logicalBytes: 4096
        )
        let f2 = IndexedFile(
            id: "beta", path: sandbox.appendingPathComponent("Developer/Beta/.build").path, root: sandbox.appendingPathComponent("Developer").path,
            identity: FileIdentity(device: 1, inode: 101, size: 2048, modified: 2, changed: 2),
            allocatedBytes: 0, category: .cache, modifiedAt: now, eligible: false, reason: "inventory_only", confidence: "inventory",
            storageCategory: .developerCaches, titleES: "Beta Sparse", titleEN: "Beta Sparse", logicalBytes: 2048
        )
        let f3 = IndexedFile(
            id: "gamma", path: sandbox.appendingPathComponent("Downloads/Gamma.dmg").path, root: sandbox.appendingPathComponent("Downloads").path,
            identity: FileIdentity(device: 1, inode: 102, size: 8192, modified: 3, changed: 3),
            allocatedBytes: 8192, category: .other, modifiedAt: now, eligible: false, reason: "inventory_only", confidence: "inventory",
            storageCategory: .downloadsAndInstallers, titleES: "Gamma", titleEN: "Gamma", logicalBytes: 8192
        )

        var result = ScanResult()
        result.files = [f1, f2, f3]
        result.finishedAt = now
        result.rebuildCategoryAggregates()
        state.scan = result
        state.syncScanAggregates()
        state.page = .findings
        state.selected = ["alpha"]

        // Rapid query typing, clearing, zero-match, and category switches
        state.query = "alpha"
        XCTAssertEqual(state.filteredFiles.map(\.id), ["alpha"])
        XCTAssertEqual(state.spaceMap(filtered: true).totalAllocatedBytes, 4096)

        state.query = "missing-pattern"
        XCTAssertTrue(state.filteredFiles.isEmpty)
        XCTAssertEqual(state.spaceMap(filtered: true).totalAllocatedBytes, 0)

        state.query = ""
        state.category = StorageCategory.developerCaches.rawValue
        XCTAssertEqual(state.filteredFiles.map(\.id), ["beta"])
        XCTAssertEqual(state.spaceMap(filtered: true).totalAllocatedBytes, 0)
        XCTAssertEqual(state.spaceMap(filtered: true).totalLogicalBytes, 2048)

        state.category = "all"
        state.query = "gamma"

        // Runtime ES / EN / System and appearance changes preserve state and keep closed polling quiet
        state.language = "en"
        XCTAssertEqual(state.selected, ["alpha"])
        XCTAssertEqual(state.page, .findings)
        XCTAssertEqual(state.query, "gamma")
        state.language = "es"
        state.language = "system"
        state.appearance = "dark"
        state.appearance = "light"
        state.appearance = "system"
        XCTAssertFalse(state.liveMetrics.isMenuVisible)
        XCTAssertFalse(state.liveMetrics.isWindowPollingActive)
        XCTAssertFalse(state.liveMetrics.isBreakdownPollingActive)

        // Scenario 10: read-only status query while an operation flag / confirmation state is active
        state.operating = true
        let status = try await state.handle(IPCRequest(command: "status"))
        XCTAssertEqual(status.object?["operating"], .bool(true))
        XCTAssertEqual(status.object?["files"], .number(3))
        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "intact")
    }
}
