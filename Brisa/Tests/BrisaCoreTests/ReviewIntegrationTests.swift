import XCTest
import Darwin
@testable import BrisaCore

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ScanProgress] = []
    func append(_ value: ScanProgress) { lock.lock(); defer { lock.unlock() }; values.append(value) }
    var snapshot: [ScanProgress] { lock.lock(); defer { lock.unlock() }; return values }
}

final class ReviewIntegrationTests: XCTestCase {
    private func indexed(_ path: String, allocated: Int64 = 4096, logical: Int64 = 1_000_000, children: Int = 1, modified: Date = Date(timeIntervalSince1970: 1)) -> IndexedFile {
        IndexedFile(id: path, path: path, root: "/Users/test/Library/Caches",
            identity: FileIdentity(device: 1, inode: 1, size: logical, modified: 1, changed: 1),
            allocatedBytes: allocated, category: .cache, modifiedAt: modified,
            eligible: true, reason: "old_known_extension", confidence: "medium", childCount: children)
    }

    func testReclaimableUsesAllocatedBytesIncludingZeroSparseAllocation() {
        let sparse = indexed("/Users/test/Library/Caches/sparse.cache", allocated: 0, logical: 1_000_000_000)
        let small = indexed("/Users/test/Library/Caches/small.cache")
        XCTAssertEqual(sparse.reclaimableBytes, 0)
        XCTAssertEqual(small.reclaimableBytes, small.allocatedBytes)
        var scan = ScanResult(); scan.files = [sparse, small]; scan.rebuildCategoryAggregates()
        XCTAssertEqual(scan.reclaimableAllocatedBytes, scan.files.reduce(0) { $0 + $1.reclaimableBytes })
        XCTAssertEqual(scan.logicalBytes, 1_001_000_000)
    }

    func testEligibilityEvaluationUsesPhysicalAllocationForRealSparseFile() throws {
        let f = try Fixture(), url = try f.file("sparse.cache", size: 0)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 1_000_000_000); try handle.close()
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-45 * 86400)], ofItemAtPath: url.path)
        var seen = Set<InodeKey>(), examined = 0
        let measurement = try XCTUnwrap(StorageMeasurement.measure(path: url.path, category: .appCaches,
            readPolicy: ReadAuthorizationPolicy(home: f.home.path, allowSystemLocations: false),
            claimedPaths: [], neverTouchedPaths: [], seenInodes: &seen, cancellation: CancellationFlag(), examinedCounter: &examined))
        let rule = CatalogRule(id: "sparse", sourceGroup: "fixture", isPrimaryCategoryGroup: true,
            displayCategory: StorageCategory.appCaches.rawValue, titleES: "Fixture", titleEN: "Fixture",
            explanationES: "Fixture", explanationEN: "Fixture", patterns: [url.path], tier: .regenerable, listOnly: false)
        let result = SelectionPolicy.evaluate(rule: rule, measurement: measurement, safetyPolicy: try f.policy(),
            snapshot: SystemEnvironmentSnapshot(), openFileCheck: { _ in [] })
        XCTAssertTrue(result.eligible)
        XCTAssertEqual(result.reclaimableBytes, measurement.allocatedBytes)
        XCTAssertLessThan(result.reclaimableBytes, measurement.logicalBytes)
    }

    func testPartialDetailsSurviveReaggregation() {
        var scan = ScanResult()
        scan.files = [indexed("/Users/test/Library/Caches/a.cache")]
        scan.categories = [CategoryReport(category: .appCaches, status: .partial,
            statusNoteES: "3 rutas sin acceso", statusNoteEN: "3 inaccessible paths")]
        scan.rebuildCategoryAggregates()
        XCTAssertEqual(scan.categories.first?.statusNoteES, "3 rutas sin acceso")
        XCTAssertEqual(scan.categories.first?.statusNoteEN, "3 inaccessible paths")
        XCTAssertFalse(scan.complete)
    }

    func testPartialCountsUpdateAfterMutationWithoutLosingReasons() {
        var scan = ScanResult()
        scan.files = [indexed("/Users/test/Library/Caches/remaining.cache")]
        scan.categories = [CategoryReport(category: .appCaches, status: .partial, itemCount: 2,
            statusNoteES: "Resultados parciales (2 elementos · 3 rutas sin acceso)",
            statusNoteEN: "Partial results (2 items · 3 inaccessible paths)")]
        scan.rebuildCategoryAggregates()
        XCTAssertEqual(scan.categories.first?.statusNoteES, "Resultados parciales (1 elementos · 3 rutas sin acceso)")
        XCTAssertEqual(scan.categories.first?.statusNoteEN, "Partial results (1 items · 3 inaccessible paths)")
        XCTAssertEqual(scan.categories.first?.itemCount, 1)
    }

    func testOthersCountsIndexedEntriesRatherThanChildren() {
        var scan = ScanResult()
        scan.files = (0..<12).map { indexed("/Users/test/Library/Caches/\($0)", allocated: Int64(4096 + $0), children: 100) }
        scan.finishedAt = Date()
        let map = SpaceMapBuilder.build(from: scan, category: .appCaches, maxVisibleTiles: 4, language: "en")
        XCTAssertEqual(map.tiles.reduce(0) { $0 + $1.itemCount }, map.totalItemCount)
        let others = map.tiles.first { $0.isOthersBucket }!
        XCTAssertEqual(others.itemCount, others.groupedFileIDs.count)
        XCTAssertEqual(others.title, "Others (9 items)")
        XCTAssertEqual(map.tiles.reduce(0) { $0 + $1.allocatedBytes }, map.totalAllocatedBytes)
    }

    func testCLIExposesCategoryFilterAndRejectsMalformedQueries() throws {
        XCTAssertEqual(try CLIOptions(["categories", "--category", "app_caches"]).arguments, ["--category", "app_caches"])
        for args in [["categories", "--category"], ["categories", "--category", "unknown"], ["categories", "--bad", "app_caches"]] {
            XCTAssertThrowsError(try CLIOptions(args))
        }
        for args in [["--search"], ["--limit", "501"], ["--limit", "-2"], ["--limit", "bad"], ["--bad", "yes"], ["--search", "a", "--search", "b"]] {
            XCTAssertThrowsError(try CLIOptions.validateFindingsArguments(args))
        }
        for name in ["orphans", "worktrees", "diagnostics", "spacemap"] { XCTAssertTrue(CLIOptions.help.contains(name)) }
    }

    func testIPCValidationErrorRetainsRequestCorrelationID() throws {
        let f = try Fixture(), path = f.home.appendingPathComponent("ipc/control.sock").path
        let server = IPCServer(path: path)
        try server.start { IPCResponse(id: $0.id, result: .bool(true)) }; defer { server.stop() }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0); XCTAssertGreaterThanOrEqual(fd, 0); defer { close(fd) }
        IPCSocket.configure(fd, timeout: 2)
        var address = try IPCSocket.address(path)
        let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        XCTAssertEqual(connected, 0)
        let request = IPCRequest(command: "status", version: 2)
        try IPCSocket.send(request, to: fd)
        let response = try IPCSocket.receive(IPCResponse.self, from: fd, timeout: 1)
        XCTAssertEqual(response.id, request.id); XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error?.code, "invalid_request")
    }

    func testIPCReadsDoNotQueueBehindMutationAndSecondMutationIsRejected() throws {
        let f = try Fixture(), path = f.home.appendingPathComponent("ipc/control.sock").path
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let finished = expectation(description: "blocked mutation finished")
        let server = IPCServer(path: path)
        try server.start { request in
            if request.command == "clean" { entered.signal(); _ = release.wait(timeout: .now() + 3) }
            return IPCResponse(id: request.id, result: .bool(true))
        }
        defer { release.signal(); wait(for: [finished], timeout: 4); server.stop() }
        DispatchQueue.global().async {
            _ = try? IPCClient.call(IPCRequest(command: "clean"), path: path, timeout: 4)
            finished.fulfill()
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        XCTAssertTrue(try IPCClient.call(IPCRequest(command: "status"), path: path, timeout: 1).ok)
        XCTAssertFalse(try IPCClient.call(IPCRequest(command: "protect", arguments: ["/tmp/test"]), path: path, timeout: 1).ok)
    }

    func testIPCReceiveHonorsOverallCallerDeadline() throws {
        var sockets: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        defer { close(sockets[0]); close(sockets[1]) }
        IPCSocket.configure(sockets[0], timeout: 5)
        let start = Date()
        XCTAssertThrowsError(try IPCSocket.receive(IPCRequest.self, from: sockets[0], timeout: 0.08))
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }

    func testLsofBatchFailureIsIsolatedWithoutIgnoringPerPathWarnings() throws {
        var queries: [[String]] = []
        let inspector = ScanOpenFileInspector(paths: ["/tmp/a", "/tmp/b"], control: ScanControl()) { paths, _ in
            queries.append(paths)
            return CommandResult(status: 1, output: "", error: paths.count == 1 && paths[0] == "/tmp/a" ? "" : "lsof: missing path", timedOut: false)
        }
        XCTAssertEqual(try inspector.openPIDs("/tmp/a"), [])
        XCTAssertThrowsError(try inspector.openPIDs("/tmp/b"))
        XCTAssertEqual(queries, [["/tmp/a", "/tmp/b"], ["/tmp/a"], ["/tmp/b"]])
        XCTAssertEqual(try inspector.openPIDs("/tmp/a"), [])
        XCTAssertEqual(queries.count, 3)
    }

    func testLsofSinglePathRetryBudgetIsBounded() {
        var count = 0
        let paths = (0..<20).map { "/tmp/test-\($0)" }
        let inspector = ScanOpenFileInspector(paths: paths, control: ScanControl()) { _, _ in
            count += 1
            return CommandResult(status: 1, output: "", error: "unknown access", timedOut: false)
        }
        for path in paths { XCTAssertThrowsError(try inspector.openPIDs(path)) }
        XCTAssertEqual(count, 9) // One batch and at most eight isolated retries.
    }

    func testAppContainerExceptionsRequireExactContainerNames() {
        let policy = ReadAuthorizationPolicy(home: "/Users/test", avoidInteractiveTCCPrompts: true)
        XCTAssertFalse(policy.requiresUnauthedTCCPrompt("/Users/test/Library/Containers/com.docker.docker/Data"))
        XCTAssertTrue(policy.requiresUnauthedTCCPrompt("/Users/test/Library/Containers/com.docker.docker.fake/Data"))
        XCTAssertFalse(policy.requiresUnauthedTCCPrompt("/Users/test/Library/Group Containers/ABCDEFGHIJ.dev.orbstack/data"))
        for name in ["evil.dev.orbstack.fake", "ABCDEFGHIJ.fake.dev.orbstack", "short.dev.orbstack"] {
            XCTAssertTrue(policy.requiresUnauthedTCCPrompt("/Users/test/Library/Group Containers/\(name)/data"), name)
        }
    }

    func testCatalogRejectsDuplicateRulesAndIncompleteCategories() throws {
        let f = try Fixture(), loaded = try CatalogLoader.load()
        let original = try JSONSerialization.jsonObject(with: JSONEncoder().encode(loaded.catalog)) as! [String: Any]
        let url = f.home.appendingPathComponent("catalog.json")
        var duplicate = original
        var rules = original["rules"] as! [[String: Any]]; rules.append(rules[0]); duplicate["rules"] = rules
        try JSONSerialization.data(withJSONObject: duplicate).write(to: url)
        XCTAssertThrowsError(try CatalogLoader.load(url: url))
        var missing = original; missing["categories"] = []
        try JSONSerialization.data(withJSONObject: missing).write(to: url)
        XCTAssertThrowsError(try CatalogLoader.load(url: url))
    }

    func testOrphanCancellationAndDeadlineAreNotMalformedMetadata() throws {
        let f = try Fixture(), policy = ReadAuthorizationPolicy(home: f.home.path)
        let flag = CancellationFlag(); flag.cancel()
        let cancelled = OrphanBuildDetector.inspect(buildDirectory: f.root.path, readPolicy: policy, control: ScanControl(cancellation: flag))
        XCTAssertEqual(cancelled.status, .cancelled)
        let expired = OrphanBuildDetector.inspect(buildDirectory: f.root.path, readPolicy: policy, control: ScanControl(deadline: .distantPast))
        XCTAssertEqual(expired.status, .partial)
        XCTAssertFalse(expired.selectionAllowed)
    }

    func testDateFiltersMatchTheirStrictLabelsAndFindNestedHiddenFolders() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        let file = indexed("/Users/test/Projects/demo/.venv/cache.bin")
        var query = InventoryQuery(); query.home = "/Users/test"; query.now = now; query.locationFilter = "hidden"
        XCTAssertEqual(query.apply(to: [file]).count, 1)
        query.locationFilter = "all"
        for (filter, age) in [("lt24h", 86400.0), ("gt7d", 7 * 86400.0), ("gt30d", 30 * 86400.0)] {
            query.dateFilter = filter
            let boundary = indexed(file.path, modified: now.addingTimeInterval(-age))
            XCTAssertTrue(query.apply(to: [boundary]).isEmpty, filter)
        }
    }

    func testCategoryReportsCountExtendedRulesAndPublishCategoryProgress() throws {
        let f = try Fixture()
        _ = try f.file("a.cache"); _ = try f.file("b.cache")
        let loaded = try CatalogLoader.load()
        let rules = [true, false].enumerated().map { i, primary in
            CatalogRule(id: "test-\(i)", sourceGroup: "fixture", isPrimaryCategoryGroup: primary,
                displayCategory: StorageCategory.appCaches.rawValue, titleES: "Fixture", titleEN: "Fixture",
                explanationES: "Fixture", explanationEN: "Fixture",
                patterns: ["~/Library/Caches/test.brisa/" + (i == 0 ? "a.cache" : "b.cache")])
        }
        let catalog = StorageCatalog(schemaVersion: 1, catalogName: "rule-count-fixture", categories: loaded.catalog.categories, rules: rules)
        let url = f.home.appendingPathComponent("catalog.json")
        try JSONEncoder().encode(catalog).write(to: url)
        let recorder = ProgressRecorder()
        let scan = CategoryDetector.scan(configuration: InventoryScanConfiguration(home: f.home.path,
            allowSystemLocations: false, maxEntries: 500, timeLimit: 5, catalogURL: url,
            environmentSnapshot: SystemEnvironmentSnapshot()), onProgress: { recorder.append($0) })
        let progress = recorder.snapshot
        let report = try XCTUnwrap(scan.categories.first { $0.category == .appCaches })
        XCTAssertEqual(report.definedRuleCount, 2)
        XCTAssertEqual(report.matchedRuleCount, 2)
        XCTAssertEqual(report.itemCount, 2)
        XCTAssertTrue(progress.contains { $0.categories.contains { $0.category == .appCaches && $0.status == .scanning } })
        XCTAssertEqual(progress.last?.categories, scan.categories)
    }

    func testProjectArtifactDoesNotTraverseRootDeniedByReadPolicy() throws {
        let f = try Fixture()
        let project = f.home.appendingPathComponent("Developer/demo")
        let artifact = project.appendingPathComponent(".build")
        try FileManager.default.createDirectory(at: artifact, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: artifact.appendingPathComponent("link").path, withDestinationPath: "/missing")
        let policy = ReadAuthorizationPolicy(home: f.home.path, projectRoots: [project.path], protectedPaths: [artifact.path])
        let result = WorktreeAndProjectDetector.inspectSingleProjectArtifact(artifactPath: artifact.path,
            artifactName: ".build", projectRoot: project.path, anchorFile: "Package.swift", ecosystem: "Swift",
            readPolicy: policy, checkActiveProcesses: false)
        XCTAssertEqual(result.state, .blockedUnverifiedGitOrUsage)
        XCTAssertFalse(result.containsSymlink, "Denied tree must not be traversed to discover its children")
        XCTAssertFalse(result.selectionAllowed)
    }

    func testProjectArtifactStopsAtNestedProtectedDirectory() throws {
        let f = try Fixture()
        let project = f.home.appendingPathComponent("Developer/demo")
        let artifact = project.appendingPathComponent(".build")
        let blocked = artifact.appendingPathComponent("blocked")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: artifact.appendingPathComponent("object.o"))
        try FileManager.default.createSymbolicLink(atPath: blocked.appendingPathComponent("link").path, withDestinationPath: "/missing")
        let policy = ReadAuthorizationPolicy(home: f.home.path, projectRoots: [project.path], protectedPaths: [blocked.path])
        let result = WorktreeAndProjectDetector.inspectSingleProjectArtifact(artifactPath: artifact.path,
            artifactName: ".build", projectRoot: project.path, anchorFile: "Package.swift", ecosystem: "Swift",
            readPolicy: policy, checkActiveProcesses: false)
        XCTAssertEqual(result.state, .blockedUnverifiedGitOrUsage)
        XCTAssertFalse(result.containsSymlink)
        XCTAssertFalse(result.usageVerified)
    }

    func testOversizedAggregateRemainsPartialWithoutCrashingMapsOrWrappingBytes() {
        var scan = ScanResult()
        scan.files = [indexed("/Users/test/Library/Caches/huge", allocated: .max, logical: .max),
                      indexed("/Users/test/Library/Caches/extra", allocated: 1, logical: 1)]
        scan.finishedAt = Date()
        scan.categories = [CategoryReport(category: .appCaches, status: .measured)]
        scan.rebuildCategoryAggregates()
        XCTAssertEqual(scan.logicalBytes, Int64.max)
        XCTAssertEqual(scan.measuredBytes, Int64.max)
        XCTAssertEqual(scan.candidateBytes, Int64.max)
        XCTAssertFalse(scan.complete)
        XCTAssertEqual(scan.categories.first?.status, .partial)
        let map = SpaceMapBuilder.build(from: scan, category: .appCaches)
        XCTAssertEqual(map.totalLogicalBytes, Int64.max)
        XCTAssertTrue(map.isPartial)
        XCTAssertEqual(map.totalItemCount, 2)
    }

    func testCoverageNotesLocalizeEveryReasonWithoutDroppingPermissionFailures() {
        let note = MeasurementNotes.describe("entry_budget_reached(2000/2000);permission_denied(3);time_budget_reached", language: "es")
        XCTAssertTrue(note.contains("entradas")); XCTAssertTrue(note.contains("rutas sin acceso: 3")); XCTAssertTrue(note.contains("tiempo"))
        XCTAssertFalse(note.contains("entry_budget")); XCTAssertFalse(note.contains("permission_denied"))
    }
}
