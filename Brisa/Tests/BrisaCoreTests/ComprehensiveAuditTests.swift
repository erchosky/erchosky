import XCTest
import Darwin
@testable import BrisaCore

final class ComprehensiveAuditTests: XCTestCase {
    // Releases an old blocking implementation, so a regression fails instead of hanging the suite.
    private func delayedFIFOWriter(_ path: String) {
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) {
            let fd = Darwin.open(path, O_WRONLY | O_NONBLOCK | O_CLOEXEC)
            if fd >= 0 { close(fd) }
        }
    }

    func testPrivateStateRejectsFIFOWithoutWaitingForWriter() throws {
        let f = try Fixture(), store = try f.store()
        let path = store.directory.appendingPathComponent("preferences.json").path
        XCTAssertEqual(mkfifo(path, 0o600), 0)
        delayedFIFOWriter(path)
        let start = Date()
        XCTAssertThrowsError(try store.read("preferences.json", as: Preferences.self))
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.3)
    }

    func testVMHeaderRejectsFIFOWithoutWaitingForWriter() throws {
        let f = try Fixture(), path = f.root.appendingPathComponent("disk.qcow2").path
        XCTAssertEqual(mkfifo(path, 0o600), 0)
        delayedFIFOWriter(path)
        let start = Date()
        XCTAssertNil(StorageMeasurement.inspectVMDiskVirtualCapacity(path: path,
            category: .vmContainers, logical: 32, allocated: 0))
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.3)
    }

    func testCleanupRootMustBeInsideCachesOrLogs() throws {
        let f = try Fixture()
        for relative in ["Projects", "Library", "Library/CachesSibling"] {
            let path = f.home.appendingPathComponent(relative).path
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            XCTAssertThrowsError(try SafetyPolicy(roots: [path], home: f.home.path), relative)
        }
        XCTAssertNoThrow(try f.policy())
    }

    func testPartialIndexedFileCannotBeRevalidatedForCleanup() throws {
        let f = try Fixture(), url = try f.file(), policy = try f.policy()
        var file = try policy.inspect(url.path)
        file.isPartial = true
        XCTAssertThrowsError(try policy.revalidate(file))
    }

    func testEmptyMeasurementsStillConsumeTheScanEntryBudget() throws {
        let f = try Fixture()
        let folder = f.root.appendingPathComponent("opaque")
        for i in 0..<10 { _ = try f.file(".env-\(i)", directory: folder) }
        let rule = CatalogRule(id: "audit-empty", sourceGroup: "audit", isPrimaryCategoryGroup: true,
            displayCategory: StorageCategory.appCaches.rawValue, titleES: "Prueba", titleEN: "Test",
            explanationES: "Fixture", explanationEN: "Fixture",
            patterns: ["~/Library/Caches/test.brisa/opaque"], listOnly: true)
        let catalog = StorageCatalog(schemaVersion: 1, catalogName: "empty-fixture",
            categories: try CatalogLoader.load().catalog.categories, rules: [rule])
        let url = f.home.appendingPathComponent("catalog.json")
        try JSONEncoder().encode(catalog).write(to: url)
        let scan = CategoryDetector.scan(configuration: InventoryScanConfiguration(home: f.home.path,
            allowSystemLocations: false, maxEntries: 100, timeLimit: 5, catalogURL: url,
            environmentSnapshot: SystemEnvironmentSnapshot()))
        XCTAssertTrue(scan.files.isEmpty)
        XCTAssertGreaterThanOrEqual(scan.examined, 10, "Excluded entries were still visited during measurement")
    }

    func testMissingConfiguredRootIsNotReportedAsAccessible() throws {
        let f = try Fixture(), path = f.home.appendingPathComponent("ProjectsMissing").path
        let policy = ReadAuthorizationPolicy(home: f.home.path, projectRoots: [path], allowSystemLocations: false)
        let state = policy.locationAccessState(path)
        XCTAssertNotEqual(state, .accessible)
        XCTAssertNotEqual(state, .explicitlyAuthorized)
    }

    func testDuplicateIPCStartPreservesOriginalLockAndListener() throws {
        let f = try Fixture(), path = f.home.appendingPathComponent("ipc/control.sock").path
        let server = IPCServer(path: path)
        try server.start { IPCResponse(id: $0.id, result: .bool(true)) }
        defer { server.stop() }
        XCTAssertThrowsError(try server.start { IPCResponse(id: $0.id, result: .bool(false)) })
        XCTAssertEqual(try IPCClient.call(IPCRequest(command: "status"), path: path, timeout: 2).result, .bool(true))
        server.stop()
        let replacement = IPCServer(path: path)
        defer { replacement.stop() }
        XCTAssertNoThrow(try replacement.start { IPCResponse(id: $0.id, result: .bool(true)) })
    }

    func testFailedIPCStartDoesNotRetainServerLock() throws {
        let f = try Fixture(), directory = f.home.appendingPathComponent("ipc")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let path = directory.appendingPathComponent("control.sock").path
        try Data("unexpected file".utf8).write(to: URL(fileURLWithPath: path))
        let failed = IPCServer(path: path)
        defer { failed.stop() }
        XCTAssertThrowsError(try failed.start { IPCResponse(id: $0.id, result: .bool(true)) })
        try FileManager.default.removeItem(atPath: path)
        let replacement = IPCServer(path: path)
        defer { replacement.stop() }
        XCTAssertNoThrow(try replacement.start { IPCResponse(id: $0.id, result: .bool(true)) })
    }

    func testCLIFlagLikeSearchValueIsNotConsumedAsGlobalOption() throws {
        let options = try CLIOptions(["findings", "--search", "--json", "--limit", "2", "--no-launch"])
        XCTAssertEqual(options.arguments, ["--search", "--json", "--limit", "2"])
        XCTAssertFalse(options.json)
        XCTAssertFalse(options.launch)
        let json = try CLIOptions(["--json", "findings", "--search", "--no-launch"])
        XCTAssertTrue(json.json)
        XCTAssertTrue(json.launch)
        XCTAssertEqual(json.arguments, ["--search", "--no-launch"])
    }

    func testCancellationHasItsOwnWireOutcomeRatherThanASafetyFailure() throws {
        let response = IPCResponse(id: "cancel", error: BrisaError.cancelled)
        let decoded = try JSONDecoder().decode(IPCResponse.self, from: JSONEncoder().encode(response))
        XCTAssertFalse(decoded.ok)
        XCTAssertEqual(decoded.error?.code, "cancelled")
        XCTAssertNil(decoded.result)
    }

    func testReviewableInvariantIsSharedByQueriesAggregatesAndAgentOpinions() throws {
        let f = try Fixture(), url = try f.file()
        let original = try f.policy().inspect(url.path)
        XCTAssertTrue(original.isReviewable)
        for change in 0..<6 {
            var file = original
            switch change {
            case 0: file.isPartial = true
            case 1: file.isDirectory = true
            case 2: file.selectionAllowed = false
            case 3: file.inventoryOnly = true
            case 4: file.cleanupEligibility = .lockedNeverSelect
            default: file.dataKind = .never
            }
            XCTAssertFalse(file.isReviewable)
            XCTAssertFalse(InventoryQuery.matchesCategory(file, filter: "eligible"))
            XCTAssertTrue(InventoryQuery.matchesCategory(file, filter: "inventory"))
            var scan = ScanResult(); scan.files = [file]; scan.rebuildCategoryAggregates()
            XCTAssertEqual(scan.reclaimableAllocatedBytes, 0)
            XCTAssertEqual(scan.categories.first { $0.category == file.storageCategory }?.eligibleCount, 0)
            XCTAssertThrowsError(try AgentValidator.validate([AgentConclusion(fileID: file.id,
                measuredSize: file.size, explanation: "Fixture", confidence: 1)], index: [file]))
        }
    }

    func testInstalledAppsIncludeVendorSubfoldersButDoNotTraverseBundlesOrLinks() throws {
        let f = try Fixture(), apps = f.home.appendingPathComponent("Applications")
        let app = apps.appendingPathComponent("Vendor/Nested.app")
        let embedded = app.appendingPathComponent("Contents/Helpers/Private.app")
        try FileManager.default.createDirectory(at: embedded, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "dev.fixture.nested", "CFBundleName": "Nested", "CFBundlePackageType": "APPL"]
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        try FileManager.default.createSymbolicLink(at: apps.appendingPathComponent("Alias.app"), withDestinationURL: app)
        let discovered = ApplicationDiscovery.discover(in: [apps.path])
        XCTAssertEqual(discovered.urls.map(\.path), [app.path])
        XCTAssertTrue(discovered.complete)
        let snapshot = SystemEnvironmentSnapshot.capture(home: f.home.path, includeSystemApps: false)
        XCTAssertTrue(snapshot.installedBundleIDs.contains("dev.fixture.nested"))
        XCTAssertFalse(SelectionPolicy.isPlausibleUninstalledLeftover(path: f.home.path + "/Library/Preferences/dev.fixture.nested.plist",
            ruleID: "preferences-leftovers", snapshot: snapshot))
    }

    func testIncompleteApplicationDiscoveryCannotClaimUninstalledLeftovers() throws {
        let f = try Fixture()
        let result = ApplicationDiscovery.discover(in: [f.root.path], maxEntries: 0)
        XCTAssertFalse(result.complete)
        let snapshot = SystemEnvironmentSnapshot(applicationInspectionComplete: false)
        XCTAssertFalse(SelectionPolicy.isPlausibleUninstalledLeftover(path: f.home.path + "/Library/Application Support/UnknownApp",
            ruleID: "app-support-leftovers", snapshot: snapshot))
    }

    func testAllDiscoveredAgentCommandsAlsoPauseCleanupWhenRunning() {
        for name in AgentDiscovery.executableNames {
            XCTAssertTrue(ProcessInspector.isAgentExecutable("/usr/local/bin/" + name), name)
        }
        XCTAssertFalse(ProcessInspector.isAgentExecutable("/Applications/Codex.app/Contents/MacOS/codex"))
        XCTAssertFalse(ProcessInspector.isAgentExecutable("/usr/local/bin/unrelated"))
    }

    func testContextualEntryCapsRemainExplicitPartialCoverageWithoutATimeout() throws {
        let f = try Fixture()
        for i in 0..<8 { _ = try f.file("entry-\(i).cache") }
        let policy = ReadAuthorizationPolicy(home: f.home.path, allowSystemLocations: false)
        let gitControl = ScanControl()
        _ = WorktreeAndProjectDetector.scanWorktrees(authorizedRoots: [f.root.path], readPolicy: policy,
            maxVisitedEntries: 2, checkActiveProcesses: false, control: gitControl)
        XCTAssertFalse(gitControl.shouldStop)
        XCTAssertTrue(gitControl.isPartial)
        XCTAssertTrue(gitControl.coverage.reasons.contains("git_entry_limit"))
        let artifactControl = ScanControl()
        _ = WorktreeAndProjectDetector.scanProjectArtifacts(authorizedRoots: [f.root.path], readPolicy: policy,
            maxVisitedEntries: 2, checkActiveProcesses: false, control: artifactControl)
        XCTAssertFalse(artifactControl.shouldStop)
        XCTAssertTrue(artifactControl.isPartial)
        XCTAssertTrue(artifactControl.coverage.reasons.contains("project_entry_limit"))
    }

    func testContextualDepthCapIsPartialWhileACompleteEmptyFolderIsNot() throws {
        let f = try Fixture(), policy = ReadAuthorizationPolicy(home: f.home.path, allowSystemLocations: false)
        let emptyControl = ScanControl()
        _ = WorktreeAndProjectDetector.scanWorktrees(authorizedRoots: [f.root.path], readPolicy: policy,
            maxDepth: 0, checkActiveProcesses: false, control: emptyControl)
        XCTAssertFalse(emptyControl.isPartial)
        try FileManager.default.createDirectory(at: f.root.appendingPathComponent("Nested"), withIntermediateDirectories: true)
        let cappedControl = ScanControl()
        _ = WorktreeAndProjectDetector.scanWorktrees(authorizedRoots: [f.root.path], readPolicy: policy,
            maxDepth: 0, checkActiveProcesses: false, control: cappedControl)
        XCTAssertTrue(cappedControl.isPartial)
    }

    func testIPCRejectsSpecialOrSharedLockFiles() throws {
        let f = try Fixture(), directory = f.home.appendingPathComponent("ipc")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let lock = directory.appendingPathComponent("server.lock").path
        XCTAssertEqual(mkfifo(lock, 0o600), 0)
        delayedFIFOWriter(lock)
        let server = IPCServer(path: directory.appendingPathComponent("control.sock").path)
        defer { server.stop() }
        let start = Date()
        XCTAssertThrowsError(try server.start { IPCResponse(id: $0.id, result: .bool(true)) })
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.3)
        try FileManager.default.removeItem(atPath: lock)
        try Data().write(to: URL(fileURLWithPath: lock))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: lock)
        XCTAssertThrowsError(try server.start { IPCResponse(id: $0.id, result: .bool(true)) })
    }

    func testContextualSkippedTCCRootCannotClaimCompleteCoverage() throws {
        let f = try Fixture(), root = f.home.appendingPathComponent("Documents/Projects")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let policy = ReadAuthorizationPolicy(home: f.home.path, projectRoots: [root.path],
            allowSystemLocations: false, avoidInteractiveTCCPrompts: true)
        let control = ScanControl()
        _ = WorktreeAndProjectDetector.scanProjectArtifacts(authorizedRoots: [root.path], readPolicy: policy,
            checkActiveProcesses: false, control: control)
        XCTAssertTrue(control.isPartial)
        XCTAssertTrue(control.coverage.reasons.contains("project_authorization_required"))
    }
}
