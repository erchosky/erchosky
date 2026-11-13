import XCTest
import Darwin
@testable import BrisaCore

final class CurrentAuditTests: XCTestCase {
    private func rule(_ pattern: String) -> CatalogRule {
        CatalogRule(id: "audit-budget", sourceGroup: "audit", isPrimaryCategoryGroup: true,
            displayCategory: StorageCategory.appCaches.rawValue, titleES: "Prueba", titleEN: "Test",
            explanationES: "Fixture", explanationEN: "Fixture", patterns: [pattern], listOnly: true)
    }

    private func indexed(_ path: String = "/Users/test/Library/Caches/a.cache", allocated: Int64 = 4096,
                         logical: Int64 = 4096) -> IndexedFile {
        IndexedFile(id: path, path: path, root: "/Users/test/Library/Caches",
            identity: FileIdentity(device: 1, inode: 1, size: logical, modified: 1, changed: 1),
            allocatedBytes: allocated, category: .cache, modifiedAt: Date(timeIntervalSince1970: 1),
            eligible: true, reason: "old_known_extension", confidence: "medium")
    }

    func testDiscoveryLeavesBudgetToMeasureFoundCandidates() throws {
        let f = try Fixture()
        for i in 0..<160 { _ = try f.file("item-\(i).dat", size: 8) }
        let loaded = try CatalogLoader.load()
        let catalog = StorageCatalog(schemaVersion: 1, catalogName: "budget-fixture",
            categories: loaded.catalog.categories, rules: [rule("~/Library/Caches/test.brisa/*")])
        let url = f.home.appendingPathComponent("catalog.json")
        try JSONEncoder().encode(catalog).write(to: url)
        let scan = CategoryDetector.scan(configuration: InventoryScanConfiguration(home: f.home.path,
            allowSystemLocations: false, maxEntries: 100, timeLimit: 5, catalogURL: url,
            environmentSnapshot: SystemEnvironmentSnapshot()))
        XCTAssertFalse(scan.files.isEmpty, "Discovery must not consume the entire measurement budget")
        XCTAssertLessThanOrEqual(scan.examined, 100)
        XCTAssertFalse(scan.complete)
    }

    func testNonMatchingDirectoryEntriesStillConsumeDiscoveryBudget() throws {
        let f = try Fixture()
        for i in 0..<40 { _ = try f.file("data-\(i).txt", size: 1) }
        var stats = PatternMatchStats()
        let hits = PatternMatcher.expand(rule: rule("~/Library/Caches/test.brisa/*.cache"),
            readPolicy: ReadAuthorizationPolicy(home: f.home.path, allowSystemLocations: false),
            claimedPaths: [], neverTouchedPaths: [], cancellation: CancellationFlag(),
            maxEntriesPerRule: 10, stats: &stats)
        XCTAssertTrue(hits.isEmpty)
        XCTAssertEqual(stats.examinedEntries, 10)
        XCTAssertTrue(stats.hitBudgetOrCancelled)
    }

    func testExpiredPatternDeadlineStopsBeforeEnumerating() throws {
        let f = try Fixture()
        _ = try f.file()
        var stats = PatternMatchStats()
        stats.deadline = .distantPast
        let hits = PatternMatcher.expand(rule: rule("~/Library/Caches/test.brisa/*"),
            readPolicy: ReadAuthorizationPolicy(home: f.home.path, allowSystemLocations: false),
            claimedPaths: [], neverTouchedPaths: [], cancellation: CancellationFlag(), stats: &stats)
        XCTAssertTrue(hits.isEmpty)
        XCTAssertEqual(stats.examinedEntries, 0)
        XCTAssertTrue(stats.hitBudgetOrCancelled)
    }

    func testUnexecutedOrDeniedScanCannotBecomeCompleteByReaggregating() {
        var scan = ScanResult()
        scan.categories = []
        scan.rebuildCategoryAggregates()
        XCTAssertFalse(scan.complete)
        scan.finishedAt = Date()
        scan.categories = [CategoryReport(category: .appCaches, status: .noAccess)]
        scan.rebuildCategoryAggregates()
        XCTAssertFalse(scan.complete)
    }

    func testCategoryAndGlobalReclaimableUseSameAllocatedUnit() throws {
        var scan = ScanResult()
        scan.files = [indexed(allocated: 4096, logical: 64 * 1_048_576)]
        scan.rebuildCategoryAggregates()
        let category = try XCTUnwrap(scan.categories.first { $0.category == .appCaches })
        XCTAssertEqual(category.reclaimableBytes, scan.reclaimableAllocatedBytes)
        XCTAssertEqual(category.reclaimableBytes, 4096)
    }

    func testBatchOpenFileInspectionFindsHolderWithoutBlockingUnopenedSibling() throws {
        let f = try Fixture()
        let held = try f.file("held.cache")
        let closed = try f.file("closed.cache")
        let fd = Darwin.open(held.path, O_RDONLY)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        let inspector = ScanOpenFileInspector(paths: [held.path, closed.path],
            control: ScanControl(deadline: Date().addingTimeInterval(5)))
        XCTAssertTrue(try inspector.openPIDs(held.path).contains(getpid()))
        XCTAssertEqual(try inspector.openPIDs(closed.path), [])
    }

    func testSharedCancellationStopsContextualDetectors() throws {
        let f = try Fixture()
        let flag = CancellationFlag()
        flag.cancel()
        let control = ScanControl(cancellation: flag)
        let policy = ReadAuthorizationPolicy(home: f.home.path, allowSystemLocations: false)
        XCTAssertTrue(OrphanBuildDetector.scanAll(home: f.home.path, readPolicy: policy, control: control).isEmpty)
        XCTAssertTrue(WorktreeAndProjectDetector.scanWorktrees(authorizedRoots: [f.home.path],
            readPolicy: policy, control: control).isEmpty)
        XCTAssertTrue(WorktreeAndProjectDetector.scanProjectArtifacts(authorizedRoots: [f.home.path],
            readPolicy: policy, control: control).isEmpty)
    }

    func testSharedDeadlineStopsACommandRatherThanItsPerCommandTimeout() throws {
        let start = Date()
        let result = try CommandRunner.run("/bin/sleep", ["10"], timeout: 10,
            control: ScanControl(deadline: Date().addingTimeInterval(0.15)))
        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testProtectedOrphanRootIsNotEnumerated() throws {
        let f = try Fixture()
        let base = f.home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        try FileManager.default.createDirectory(at: base.appendingPathComponent("Build"), withIntermediateDirectories: true)
        let policy = ReadAuthorizationPolicy(home: f.home.path, protectedPaths: [base.path], allowSystemLocations: false)
        XCTAssertTrue(OrphanBuildDetector.scanAll(home: f.home.path, readPolicy: policy).isEmpty)
    }

    func testOrphanMetadataCannotBeReadThroughSymlinkedParent() throws {
        let f = try Fixture()
        let build = f.home.appendingPathComponent("Library/Developer/XcodeBuildMCP/workspaces/example")
        let external = f.home.appendingPathComponent("ProtectedMetadata")
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: ["WorkspacePath": f.root.path], format: .xml, options: 0)
        try data.write(to: external.appendingPathComponent("info.plist"))
        try FileManager.default.createSymbolicLink(at: build.appendingPathComponent("DerivedData"), withDestinationURL: external)
        let result = OrphanBuildDetector.inspect(buildDirectory: build.path,
            readPolicy: ReadAuthorizationPolicy(home: f.home.path, protectedPaths: [external.path], allowSystemLocations: false))
        XCTAssertNotEqual(result.status, .activeProject)
        XCTAssertTrue(result.recordedWorkspacePaths.isEmpty)
    }

    func testFailedGitExecutableDoesNotVerifyProjectIsUntracked() throws {
        let f = try Fixture()
        let artifact = f.home.appendingPathComponent("Developer/App/.build")
        try FileManager.default.createDirectory(at: artifact, withIntermediateDirectories: true)
        _ = try f.file("output.o", directory: artifact)
        let result = WorktreeAndProjectDetector.inspectSingleProjectArtifact(artifactPath: artifact.path,
            artifactName: ".build", projectRoot: artifact.deletingLastPathComponent().path,
            anchorFile: "Package.swift", ecosystem: "swift",
            readPolicy: ReadAuthorizationPolicy(home: f.home.path, allowSystemLocations: false),
            gitExecutable: "/bin/false", checkActiveProcesses: false)
        XCTAssertEqual(result.state, .blockedUnverifiedGitOrUsage)
        XCTAssertNil(result.trackedFileCount)
    }

    func testNestedRepositoryInsideArtifactIsDetected() throws {
        let f = try Fixture()
        let artifact = f.home.appendingPathComponent("Developer/Web/dist")
        try FileManager.default.createDirectory(at: artifact.appendingPathComponent("vendor/.git"), withIntermediateDirectories: true)
        _ = try f.file("app.js", directory: artifact)
        let result = WorktreeAndProjectDetector.inspectSingleProjectArtifact(artifactPath: artifact.path,
            artifactName: "dist", projectRoot: artifact.deletingLastPathComponent().path,
            anchorFile: "package.json", ecosystem: "node",
            readPolicy: ReadAuthorizationPolicy(home: f.home.path, allowSystemLocations: false), checkActiveProcesses: false)
        XCTAssertEqual(result.state, .blockedNestedSubrepository)
    }

    func testMetadataRefreshPreservesCatalogInventoryRestrictionAndRejectsChanges() throws {
        let f = try Fixture()
        let url = try f.file()
        var item = try f.policy().inspect(url.path)
        item.eligible = false
        item.inventoryOnly = true
        item.selectionAllowed = false
        item.cleanupEligibility = .inventoryOnly
        let readPolicy = ReadAuthorizationPolicy(home: f.home.path, allowSystemLocations: false)
        let fresh = try InventoryMetadata.refresh(item, readPolicy: readPolicy)
        XCTAssertFalse(fresh.eligible)
        XCTAssertFalse(fresh.selectionAllowed)
        XCTAssertTrue(fresh.inventoryOnly)
        try Data("changed".utf8).write(to: url)
        XCTAssertThrowsError(try InventoryMetadata.refresh(item, readPolicy: readPolicy))
    }

    func testSpaceMapUsesRealCoverageReasonAndSelectedLanguage() {
        var scan = ScanResult()
        scan.finishedAt = Date()
        scan.cancelled = true
        let map = SpaceMapBuilder.build(from: scan, language: "en")
        XCTAssertEqual(map.scopeTitle, "Inventory by category")
        XCTAssertTrue(map.partialReasons.contains("Scan cancelled."))
        XCTAssertFalse(map.partialReasons.joined().localizedCaseInsensitiveContains("budget"))
        XCTAssertEqual(map.equivalentList.first?.title, map.equivalentList.first?.category?.titleEN)
    }

    func testNewScanMapIsPendingRatherThanPartialOrBudgetExceeded() {
        let map = SpaceMapBuilder.build(from: ScanResult())
        XCTAssertFalse(map.isPartial)
        XCTAssertTrue(map.partialReasons.isEmpty)
    }

    func testSparseFilteringAndStrictSizeThresholdsAreDeterministic() {
        let sparse = indexed("/Users/test/Library/Caches/sparse.raw", allocated: 0, logical: 1_000_000)
        let exact = indexed("/Users/test/Library/Caches/exact.cache", allocated: 10 * 1_048_576)
        var filter = InventoryQuery()
        filter.sizeFilter = "zero_allocated"
        XCTAssertEqual(filter.apply(to: [exact, sparse]).map(\.id), [sparse.id])
        filter.sizeFilter = "gt10m"
        XCTAssertTrue(filter.apply(to: [exact, sparse]).isEmpty)
        filter.sizeFilter = "all"
        filter.sortOrder = "name_asc"
        XCTAssertEqual(filter.apply(to: [sparse, exact]).map(\.id), [exact.id, sparse.id])
    }

    func testOverflowingSwapInputReturnsUnknownInsteadOfTrapping() {
        XCTAssertNil(SystemDiagnostics.parseSwapUsageString("total = 9999999999999999999999999999999999999999M used = 1M free = 1M"))
    }

    func testUnrepresentableVMCapacitiesStayUnknown() {
        XCTAssertNil(ByteTotals.knownSum([Int64.max, 1]))
        XCTAssertNil(ByteTotals.knownSum([-1, 4]))
        XCTAssertNil(ByteTotals.knownSum([]))
        XCTAssertEqual(ByteTotals.knownSum([32, 64]), 96)
        var scan = ScanResult()
        var a = indexed("/Users/test/a.qcow2")
        var b = indexed("/Users/test/b.qcow2")
        a.virtualCapacityBytes = Int64.max
        b.virtualCapacityBytes = Int64.max
        scan.files = [a, b]
        scan.rebuildCategoryAggregates()
        XCTAssertNil(scan.categories.first { $0.category == .appCaches }?.virtualCapacityBytes)
    }

    func testAncestorIndexHonorsPathBoundariesAndRoot() {
        let claimed: Set<String> = ["/Users/test/cache", "/Users/test/other/child"]
        XCTAssertTrue(Paths.containsAncestor(of: "/Users/test/cache/item", in: claimed))
        XCTAssertTrue(Paths.containsAncestor(of: "/Users/test/cache", in: claimed))
        XCTAssertFalse(Paths.containsAncestor(of: "/Users/test/cache-sibling/item", in: claimed))
        XCTAssertFalse(Paths.containsAncestor(of: "/Users/test/other", in: claimed))
        XCTAssertTrue(SafetyPolicy.within("/Users/test", "/"))
        XCTAssertFalse(SafetyPolicy.within("relative", "/"))
    }

    func testOversizedVMHeadersDoNotOverflowDirectoryMeasurement() throws {
        let f = try Fixture()
        var header = [UInt8](repeating: 0, count: 32)
        header[0] = 0x51; header[1] = 0x46; header[2] = 0x49; header[3] = 0xfb; header[7] = 3
        header[24] = 0x7f
        for i in 25..<32 { header[i] = 0xff }
        try Data(header).write(to: f.root.appendingPathComponent("a.qcow2"))
        try Data(header).write(to: f.root.appendingPathComponent("b.qcow2"))
        var seen = Set<InodeKey>()
        var examined = 0
        let result = StorageMeasurement.measure(path: f.root.path, category: .vmContainers,
            readPolicy: ReadAuthorizationPolicy(home: f.home.path, allowSystemLocations: false),
            claimedPaths: [], neverTouchedPaths: [], seenInodes: &seen,
            cancellation: CancellationFlag(), examinedCounter: &examined)
        XCTAssertNotNil(result)
        XCTAssertNil(result?.virtualCapacityBytes)
        XCTAssertEqual(result?.logicalBytes, 64)
    }

    func testDuplicateIndexIdentityIsRejectedWithoutCrashing() {
        let file = indexed()
        XCTAssertThrowsError(try AgentValidator.validate([], index: [file, file]))
    }

    func testPersistedInventoryPathDoesNotImplyCurrentTCCAuthorization() throws {
        let f = try Fixture()
        let downloads = f.home.path + "/Downloads"
        let configured = ReadAuthorizationPolicy(home: f.home.path, projectRoots: [downloads],
            allowSystemLocations: false, avoidInteractiveTCCPrompts: true)
        XCTAssertTrue(configured.requiresUnauthedTCCPrompt(downloads))
        XCTAssertEqual(configured.locationAccessState(downloads), .skippedInteractivePrompt)
        let authorized = ReadAuthorizationPolicy(home: f.home.path, projectRoots: [downloads],
            allowSystemLocations: false, avoidInteractiveTCCPrompts: true, authorizedPromptRoots: [downloads])
        XCTAssertFalse(authorized.requiresUnauthedTCCPrompt(downloads))
    }

    func testRecursiveProjectPatternSkipsUnauthorizedTCCRootBeforeOpening() throws {
        let f = try Fixture()
        let downloads = f.home.path + "/Downloads"
        try FileManager.default.createDirectory(atPath: downloads + "/.build", withIntermediateDirectories: true)
        let policy = ReadAuthorizationPolicy(home: f.home.path, projectRoots: [downloads],
            allowSystemLocations: false, avoidInteractiveTCCPrompts: true)
        var stats = PatternMatchStats()
        let matches = PatternMatcher.expand(rule: rule("**/.build"), readPolicy: policy,
            claimedPaths: [], neverTouchedPaths: [], cancellation: CancellationFlag(), stats: &stats)
        XCTAssertTrue(matches.isEmpty)
        XCTAssertGreaterThan(stats.accessDeniedCount, 0)
        XCTAssertEqual(stats.examinedEntries, 0)
    }

    func testDirectoryOpenRejectsFIFOAndSymbolicLinkWithoutBlocking() throws {
        let f = try Fixture()
        let fifo = f.root.path + "/named-pipe"
        XCTAssertEqual(mkfifo(fifo, 0o600), 0)
        XCTAssertNil(Paths.openDirectory(fifo))
        let symlink = f.root.path + "/link"
        try FileManager.default.createSymbolicLink(atPath: symlink, withDestinationPath: f.root.path)
        XCTAssertNil(Paths.openDirectory(symlink))
        let directory = try XCTUnwrap(Paths.openDirectory(f.root.path))
        closedir(directory)
    }

    func testFilteredMapMatchesVisibleListWithoutChangingUnfilteredSnapshot() {
        var scan = ScanResult()
        let a = indexed("/Users/test/Library/Caches/alpha.cache", allocated: 4096)
        var b = indexed("/Users/test/Library/Caches/beta.cache", allocated: 8192)
        b.eligible = false
        b.inventoryOnly = true
        scan.files = [a, b]
        scan.finishedAt = Date()
        var query = InventoryQuery()
        query.query = "alpha"
        let visible = query.apply(to: scan.files)
        let map = SpaceMapBuilder.build(from: scan, category: .appCaches, query: query)
        XCTAssertEqual(map.totalItemCount, visible.count)
        XCTAssertEqual(map.totalAllocatedBytes, visible.reduce(0) { $0 + $1.allocatedBytes })
        XCTAssertEqual(map.equivalentList.flatMap(\.groupedFileIDs), visible.map(\.id))
        query.query = ""
        query.category = "eligible"
        XCTAssertEqual(SpaceMapBuilder.build(from: scan, query: query).totalItemCount, 1)
        XCTAssertEqual(SpaceMapBuilder.build(from: scan).totalItemCount, 2)
        XCTAssertEqual(scan.files.count, 2)
    }
}
