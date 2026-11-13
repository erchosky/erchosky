import XCTest
import Darwin
@testable import BrisaCore

final class OptimizationTests: XCTestCase {
    func testIndexedFileToJSONValueMatchesGenericEncode() throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let fullIdentity = FileIdentity(device: 16, inode: 99_123, size: 8192, modified: 1_760_000_000.25, changed: 1_760_000_001.5)
        let full = IndexedFile(
            id: "full-id",
            path: "/Users/test/Library/Caches/com.example/data.bin",
            root: "/Users/test/Library/Caches",
            identity: fullIdentity,
            allocatedBytes: 4096,
            category: .cache,
            modifiedAt: now,
            eligible: true,
            reason: "eligible",
            confidence: "high",
            storageCategory: .appCaches,
            titleES: "Cache ejemplo",
            titleEN: "Example cache",
            ruleID: "example-rule",
            sourceGroup: "Example App",
            isDirectory: true,
            childCount: 12,
            logicalBytes: 8192,
            virtualCapacityBytes: 65_536,
            reclaimableBytes: 4096,
            dataKind: .regenerable,
            inventoryOnly: false,
            selectionAllowed: true,
            cleanupEligibility: .eligible,
            usageState: UsageState(status: "idle", detail: "no_open_handles"),
            dateKind: "mtime_latest_entry",
            explanationES: "Explicación",
            explanationEN: "Explanation",
            conditionsSummary: ["aged", "idle"],
            isPartial: true,
            partialReason: "entry_budget_reached(10/10)",
            provenance: "verified_catalog",
            upstreamProvenance: RuleProvenance(
                repository: "upstream/repo",
                commit: "abc1234",
                version: "1.0.0",
                upstreamID: "up-1",
                upstreamActionKind: "cache",
                coverageRelation: "exact",
                localReviewNote: "reviewed"
            ),
            regenBehavior: "rebuilds"
        )
        XCTAssertEqual(full.toJSONValue(), try JSONValue.encode(full))

        let minimal = IndexedFile(
            id: "min-id",
            path: "/Users/test/Downloads/installer.dmg",
            root: "/Users/test/Downloads",
            identity: FileIdentity(device: 1, inode: 2, size: 1024, modified: 10, changed: 20),
            allocatedBytes: 0,
            category: .other,
            modifiedAt: Date(timeIntervalSince1970: 10),
            eligible: false,
            reason: "inventory_only",
            confidence: "inventory"
        )
        XCTAssertEqual(minimal.toJSONValue(), try JSONValue.encode(minimal))
    }

    func testPathsIsAlreadyNormalizedAndReadPolicyParity() throws {
        for sample in ["/", "/Users/test/Library/Caches", "", "Users/test", "/Users/test/", "/Users//test", "/Users/./test", "/Users/../test"] {
            XCTAssertEqual(Paths.isAlreadyNormalized(sample), Paths.normalized(sample) == sample, "Mismatch for \(sample)")
        }
        XCTAssertTrue(Paths.isAlreadyNormalized("/"))
        XCTAssertTrue(Paths.isAlreadyNormalized("/Users/test/Library/Caches"))
        XCTAssertFalse(Paths.isAlreadyNormalized("/Users/test/"))
        XCTAssertFalse(Paths.isAlreadyNormalized("/Users//test"))
        XCTAssertFalse(Paths.isAlreadyNormalized("/Users/./test"))
        XCTAssertFalse(Paths.isAlreadyNormalized("/Users/../test"))

        let f = try Fixture()
        let policy = ReadAuthorizationPolicy(
            home: f.home.path,
            projectRoots: [f.home.appendingPathComponent("Developer").path],
            protectedPaths: [f.home.appendingPathComponent("Developer/Protected").path],
            allowSystemLocations: false,
            avoidInteractiveTCCPrompts: true
        )

        XCTAssertEqual(policy.evaluate(f.home.appendingPathComponent("Library/Caches/app").path, checkSymlinks: false), .allowed)
        XCTAssertEqual(policy.evaluate(f.home.path + "/Library/Caches/app/", checkSymlinks: false), .deniedOutsideScope)
        XCTAssertEqual(policy.evaluate(f.home.appendingPathComponent("Library/Caches/../Caches/app").path, checkSymlinks: false), .deniedOutsideScope)
        XCTAssertEqual(policy.evaluate(f.home.appendingPathComponent("Library/Caches/a\u{200B}pp").path, checkSymlinks: false), .deniedOutsideScope)

        let claudeMemory = f.home.appendingPathComponent(".claude/projects/demo/memory/note.md").path
        XCTAssertEqual(policy.evaluate(claudeMemory, checkSymlinks: false), .deniedSensitive("claude_memory"))
        let brisaInternal = f.home.appendingPathComponent("Library/Caches/dev.brisa.build/tmp.json").path
        XCTAssertEqual(policy.evaluate(brisaInternal, checkSymlinks: false), .deniedSensitive("brisa_internal"))
        let mailStore = f.home.appendingPathComponent("Library/Mail/V10").path
        XCTAssertEqual(policy.evaluate(mailStore, checkSymlinks: false), .deniedSensitive("forbidden_store:Library/Mail"))
        let deniedChild = f.home.appendingPathComponent("Developer/Protected/sub").path
        XCTAssertEqual(policy.evaluate(deniedChild, checkSymlinks: false), .deniedUserProtected)
        XCTAssertTrue(policy.requiresUnauthedTCCPrompt(f.home.appendingPathComponent("Library/Caches/com.apple.Safari").path))
        XCTAssertTrue(policy.requiresUnauthedTCCPrompt(f.home.appendingPathComponent("Documents/Notes").path))
        XCTAssertFalse(policy.requiresUnauthedTCCPrompt(f.home.appendingPathComponent("Developer/demo").path))
    }

    func testWorktreeAndProjectScanAllMatchesSeparateScansAndDetectsSafetyStates() throws {
        let f = try Fixture()
        let devRoot = f.home.appendingPathComponent("Developer", isDirectory: true)

        // 1. Real Git repo with a `.worktrees` linked worktree
        let repo = devRoot.appendingPathComponent("MyRepo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try runGit(["init", "-q", repo.path])
        try runGit(["-C", repo.path, "config", "user.email", "brisa@example.com"])
        try runGit(["-C", repo.path, "config", "user.name", "Brisa"])
        try Data("hello\n".utf8).write(to: repo.appendingPathComponent("README.md"))
        try runGit(["-C", repo.path, "add", "README.md"])
        try runGit(["-C", repo.path, "commit", "-q", "-m", "init"])
        let wt = repo.appendingPathComponent(".worktrees/feature-a", isDirectory: true)
        try runGit(["-C", repo.path, "worktree", "add", "-q", "-b", "feature-a", wt.path])

        // Build artifact anchored inside the worktree repo (excluded from artifacts inside `.worktrees`)
        try Data("// swift-tools-version: 6.0\n".utf8).write(to: wt.appendingPathComponent("Package.swift"))
        let wtBuild = wt.appendingPathComponent(".build", isDirectory: true)
        try FileManager.default.createDirectory(at: wtBuild, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 64).write(to: wtBuild.appendingPathComponent("wt.o"))

        // 2. SwiftPM project (.anchoredIdleCandidate)
        let swiftProj = devRoot.appendingPathComponent("SwiftProj", isDirectory: true)
        let swiftBuild = swiftProj.appendingPathComponent(".build", isDirectory: true)
        let swiftObject = swiftBuild.appendingPathComponent("main.o")
        try FileManager.default.createDirectory(at: swiftBuild, withIntermediateDirectories: true)
        try Data("// swift-tools-version: 6.0\n".utf8).write(to: swiftProj.appendingPathComponent("Package.swift"))
        try Data(repeating: 2, count: 512).write(to: swiftObject)
        let agedDate = Date().addingTimeInterval(-7200)
        try FileManager.default.setAttributes([.modificationDate: agedDate], ofItemAtPath: swiftObject.path)
        try FileManager.default.setAttributes([.modificationDate: agedDate], ofItemAtPath: swiftBuild.path)

        // 3. Node project with internal symlink inside `dist` (.blockedContainsSymlink)
        let nodeProj = devRoot.appendingPathComponent("NodeProj", isDirectory: true)
        let dist = nodeProj.appendingPathComponent("dist", isDirectory: true)
        try FileManager.default.createDirectory(at: dist, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: nodeProj.appendingPathComponent("package.json"))
        try Data(repeating: 3, count: 256).write(to: dist.appendingPathComponent("bundle.js"))
        try FileManager.default.createSymbolicLink(atPath: dist.appendingPathComponent("escape").path, withDestinationPath: "/missing")

        // 4. Cargo project with nested `.git` inside `target` (.blockedNestedSubrepository)
        let cargoProj = devRoot.appendingPathComponent("CargoProj", isDirectory: true)
        let targetGit = cargoProj.appendingPathComponent("target/.git", isDirectory: true)
        try FileManager.default.createDirectory(at: targetGit, withIntermediateDirectories: true)
        try Data("[package]\nname=\"demo\"\n".utf8).write(to: cargoProj.appendingPathComponent("Cargo.toml"))
        try Data("ref: refs/heads/main\n".utf8).write(to: targetGit.appendingPathComponent("HEAD"))

        let policy = ReadAuthorizationPolicy(home: f.home.path, projectRoots: [devRoot.path], allowSystemLocations: false)
        let fixedNow = Date()

        let unified = WorktreeAndProjectDetector.scanAll(
            authorizedRoots: [devRoot.path],
            readPolicy: policy,
            checkActiveProcesses: false,
            now: fixedNow
        )
        let separateWorktrees = WorktreeAndProjectDetector.scanWorktrees(
            authorizedRoots: [devRoot.path],
            readPolicy: policy,
            checkActiveProcesses: false,
            now: fixedNow
        )
        let separateArtifacts = WorktreeAndProjectDetector.scanProjectArtifacts(
            authorizedRoots: [devRoot.path],
            readPolicy: policy,
            checkActiveProcesses: false,
            now: fixedNow
        )

        XCTAssertEqual(unified.worktrees, separateWorktrees)
        XCTAssertEqual(unified.projectArtifacts, separateArtifacts)
        XCTAssertEqual(unified.worktrees.count, 2)

        let byPath = Dictionary(uniqueKeysWithValues: unified.projectArtifacts.map { ($0.artifactPath, $0) })
        XCTAssertEqual(byPath[Paths.normalized(swiftProj.appendingPathComponent(".build").path)]?.state, .anchoredIdleCandidate)
        XCTAssertEqual(byPath[Paths.normalized(dist.path)]?.state, .blockedContainsSymlink)
        XCTAssertEqual(byPath[Paths.normalized(cargoProj.appendingPathComponent("target").path)]?.state, .blockedNestedSubrepository)
        XCTAssertNil(byPath[Paths.normalized(wtBuild.path)], "`.worktrees` subtree must not yield duplicate artifact entries")
    }

    func testInventoryQueryFilterUnsortedMatchesSortedFilterAndSpaceMapConsistency() {
        let now = Date()
        let f1 = IndexedFile(
            id: "1", path: "/Users/test/Library/Caches/AlphaTool/cache.db", root: "/Users/test/Library/Caches",
            identity: FileIdentity(device: 1, inode: 10, size: 4096, modified: 1, changed: 1),
            allocatedBytes: 4096, category: .cache, modifiedAt: now, eligible: true, reason: "eligible", confidence: "high",
            storageCategory: .appCaches, titleES: "Cache Alpha", titleEN: "Alpha Cache", logicalBytes: 4096
        )
        let f2 = IndexedFile(
            id: "2", path: "/Users/test/Library/Developer/Xcode/DerivedData/Beta-sparse", root: "/Users/test/Library/Developer/Xcode/DerivedData",
            identity: FileIdentity(device: 1, inode: 11, size: 8192, modified: 2, changed: 2),
            allocatedBytes: 0, category: .cache, modifiedAt: now, eligible: false, reason: "inventory_only", confidence: "inventory",
            storageCategory: .developerCaches, titleES: "Compilación Beta", titleEN: "Beta Build", logicalBytes: 8192
        )
        let f3 = IndexedFile(
            id: "3", path: "/Users/test/Downloads/GammaSetup.dmg", root: "/Users/test/Downloads",
            identity: FileIdentity(device: 1, inode: 12, size: 2048, modified: 3, changed: 3),
            allocatedBytes: 2048, category: .other, modifiedAt: now, eligible: false, reason: "inventory_only", confidence: "inventory",
            storageCategory: .downloadsAndInstallers, titleES: "Instalador Gamma", titleEN: "Gamma Installer", logicalBytes: 2048
        )

        var scan = ScanResult()
        scan.files = [f1, f2, f3]
        scan.finishedAt = now
        scan.rebuildCategoryAggregates()

        let cases: [(query: String, category: String, expectedCount: Int)] = [
            ("ALPHA", "all", 1),
            ("", "all", 3),
            ("nonexistent-xyz", "all", 0),
            ("beta", StorageCategory.developerCaches.rawValue, 1),
            ("", StorageCategory.developerCaches.rawValue, 1)
        ]
        for testCase in cases {
            var q = InventoryQuery()
            q.query = testCase.query
            q.category = testCase.category
            q.now = now
            let sorted = q.apply(to: scan.files)
            let unsorted = q.filterUnsorted(scan.files)
            XCTAssertEqual(sorted.count, testCase.expectedCount)
            XCTAssertEqual(Set(unsorted.map(\.id)), Set(sorted.map(\.id)))
            let slice = SpaceMapBuilder.build(from: scan, query: q)
            let expectedAlloc = sorted.reduce(Int64(0)) { $0 + $1.allocatedBytes }
            let expectedLogical = sorted.reduce(Int64(0)) { $0 + $1.logicalBytes }
            XCTAssertEqual(slice.totalAllocatedBytes, expectedAlloc)
            XCTAssertEqual(slice.totalLogicalBytes, expectedLogical)
            XCTAssertEqual(slice.totalItemCount, sorted.count)
        }
    }

    private func runGit(_ arguments: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = arguments
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, "git \(arguments.joined(separator: " ")) failed")
    }
}
