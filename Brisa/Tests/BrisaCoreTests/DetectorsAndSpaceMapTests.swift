import XCTest
import Darwin
@testable import BrisaCore

final class DetectorsAndSpaceMapTests: XCTestCase {

    // MARK: - 1. OrphanBuildDetector Tests

    func testOrphanBuildDetectorClassifiesActiveAndPossiblyOrphanedDerivedData() throws {
        let f = try Fixture()
        let derivedData = f.home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        let activeBuild = derivedData.appendingPathComponent("ActiveApp-abcdef123456")
        let orphanBuild = derivedData.appendingPathComponent("RemovedApp-fedcba654321")
        let existingWorkspace = f.home.appendingPathComponent("Developer/ActiveApp/ActiveApp.xcodeproj")
        let missingWorkspace = f.home.appendingPathComponent("Developer/DeletedApp/DeletedApp.xcodeproj")

        try FileManager.default.createDirectory(at: activeBuild, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: orphanBuild, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: existingWorkspace, withIntermediateDirectories: true)

        let activePlist = try PropertyListSerialization.data(
            fromPropertyList: ["WorkspacePath": existingWorkspace.path],
            format: .xml,
            options: 0
        )
        try activePlist.write(to: activeBuild.appendingPathComponent("info.plist"))

        let orphanPlist = try PropertyListSerialization.data(
            fromPropertyList: ["WorkspacePath": missingWorkspace.path],
            format: .xml,
            options: 0
        )
        let orphanPlistURL = orphanBuild.appendingPathComponent("info.plist")
        try orphanPlist.write(to: orphanPlistURL)

        // Backdate orphanBuild by 2 days so it's not treated as recently modified (<2 min)
        let oldDate = Date().addingTimeInterval(-2 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: orphanPlistURL.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: orphanBuild.path)

        let readPol = ReadAuthorizationPolicy(home: f.home.path, allowSystemLocations: false)

        let activeRes = OrphanBuildDetector.inspect(buildDirectory: activeBuild.path, readPolicy: readPol)
        XCTAssertEqual(activeRes.status, .activeProject)
        XCTAssertEqual(activeRes.existingWorkspacePaths, [Paths.normalized(existingWorkspace.path)])
        XCTAssertTrue(activeRes.inventoryOnly)
        XCTAssertFalse(activeRes.selectionAllowed)

        let orphanRes = OrphanBuildDetector.inspect(buildDirectory: orphanBuild.path, readPolicy: readPol)
        XCTAssertEqual(orphanRes.status, .possiblyOrphaned)
        XCTAssertEqual(orphanRes.missingWorkspacePaths, [Paths.normalized(missingWorkspace.path)])
        XCTAssertTrue(orphanRes.inventoryOnly)
        XCTAssertFalse(orphanRes.selectionAllowed)
    }

    func testOrphanBuildDetectorSupportsXcodeBuildMCPDaemonJSONAndSHA12AncestorMatch() throws {
        let f = try Fixture()
        let mcpRoot = f.home.appendingPathComponent("Library/Developer/XcodeBuildMCP/workspaces")
        let projectDir = f.home.appendingPathComponent("Developer/MyWorkspace")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let normalizedProject = Paths.normalized(projectDir.path)
        let hash12 = OrphanBuildDetector.sha12(normalizedProject)
        let wsBuild = mcpRoot.appendingPathComponent("MyWorkspace-\(hash12)")
        let stateDir = wsBuild.appendingPathComponent("state/daemon")
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)

        // Point workspaceRoot to a moved inner subfolder of `projectDir`, while `projectDir` itself matches `hash12`
        let innerMissing = projectDir.appendingPathComponent("RenamedSubfolder/App.xcworkspace").path
        let json = try JSONSerialization.data(withJSONObject: ["workspaceRoot": innerMissing])
        let daemonFile = stateDir.appendingPathComponent("daemon.json")
        try json.write(to: daemonFile)

        let oldDate = Date().addingTimeInterval(-3600)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: daemonFile.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: wsBuild.path)

        let readPol = ReadAuthorizationPolicy(home: f.home.path, allowSystemLocations: false)
        let res = OrphanBuildDetector.inspect(buildDirectory: wsBuild.path, readPolicy: readPol)
        XCTAssertEqual(res.status, .activeProject, "12-hex SHA-256 ancestor match must keep build classified as activeProject")
        XCTAssertTrue(res.existingWorkspacePaths.contains(normalizedProject))
    }

    func testOrphanBuildDetectorNeverMarksUnmountedVolumeOrPermissionErrorAsOrphan() throws {
        let f = try Fixture()
        let derivedData = f.home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        let externalBuild = derivedData.appendingPathComponent("ExtApp-111122223333")
        let restrictedBuild = derivedData.appendingPathComponent("RestrictedApp-444455556666")
        let fakeVolumes = f.home.appendingPathComponent("FakeVolumes")

        try FileManager.default.createDirectory(at: externalBuild, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: restrictedBuild, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fakeVolumes, withIntermediateDirectories: true)

        // 1. Unmounted volume reference under /Volumes/UnmountedSSD/...
        let unmountedPath = fakeVolumes.appendingPathComponent("UnmountedSSD/Repo/ExtApp.xcodeproj").path
        let extPlist = try PropertyListSerialization.data(
            fromPropertyList: ["WorkspacePath": unmountedPath],
            format: .xml,
            options: 0
        )
        let extPlistURL = externalBuild.appendingPathComponent("info.plist")
        try extPlist.write(to: extPlistURL)
        let oldDate = Date().addingTimeInterval(-86_400)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: extPlistURL.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: externalBuild.path)

        let readPol = ReadAuthorizationPolicy(home: f.home.path, allowSystemLocations: false)
        let extRes = OrphanBuildDetector.inspect(
            buildDirectory: externalBuild.path,
            readPolicy: readPol,
            volumesRoot: fakeVolumes.path
        )
        XCTAssertEqual(extRes.status, .unknownUnmountedVolume)
        XCTAssertNotEqual(extRes.status, .possiblyOrphaned)

        // 2. Permission denied on info.plist (chmod 000)
        let restPlistURL = restrictedBuild.appendingPathComponent("info.plist")
        try extPlist.write(to: restPlistURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: restPlistURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: restPlistURL.path)
        }
        let restRes = OrphanBuildDetector.inspect(
            buildDirectory: restrictedBuild.path,
            readPolicy: readPol,
            volumesRoot: fakeVolumes.path
        )
        if geteuid() != 0 {
            XCTAssertEqual(restRes.status, .permissionDenied)
            XCTAssertNotEqual(restRes.status, .possiblyOrphaned)
        }
    }

    // MARK: - 2. WorktreeAndProjectDetector Tests

    func testWorktreeDetectorClassifiesCleanDirtyUnpushedLockedAndFailedStates() throws {
        let f = try Fixture()
        let devRoot = f.home.appendingPathComponent("Developer")
        let mainRepo = devRoot.appendingPathComponent("MainRepo")
        let linkedClean = devRoot.appendingPathComponent("wt-clean")
        let linkedDirty = devRoot.appendingPathComponent("wt-dirty")
        let linkedUnpushed = devRoot.appendingPathComponent("wt-unpushed")
        let linkedLocked = devRoot.appendingPathComponent("wt-locked")

        try FileManager.default.createDirectory(at: mainRepo, withIntermediateDirectories: true)

        func git(_ dir: URL, _ args: [String]) throws {
            let r = try CommandRunner.run("/usr/bin/git", ["-C", dir.path] + args)
            XCTAssertEqual(r.status, 0, "git \(args) failed: \(r.error)")
        }

        try git(mainRepo, ["init", "--initial-branch=main"])
        try git(mainRepo, ["config", "user.name", "Test"])
        try git(mainRepo, ["config", "user.email", "test@example.invalid"])
        try Data("hello\n".utf8).write(to: mainRepo.appendingPathComponent("README.md"))
        try git(mainRepo, ["add", "README.md"])
        try git(mainRepo, ["commit", "-m", "initial"])

        // Create linked worktrees
        try git(mainRepo, ["worktree", "add", "-b", "feature/clean", linkedClean.path, "main"])
        try git(mainRepo, ["worktree", "add", "-b", "feature/dirty", linkedDirty.path, "main"])
        try git(mainRepo, ["worktree", "add", "-b", "feature/unpushed", linkedUnpushed.path, "main"])
        try git(mainRepo, ["worktree", "add", "-b", "feature/locked", linkedLocked.path, "main"])

        // Make linkedDirty dirty
        try Data("dirty change\n".utf8).write(to: linkedDirty.appendingPathComponent("untracked.txt"))

        // Make linkedUnpushed have an unmerged commit not on main
        try Data("unpushed work\n".utf8).write(to: linkedUnpushed.appendingPathComponent("feature.txt"))
        try git(linkedUnpushed, ["add", "feature.txt"])
        try git(linkedUnpushed, ["commit", "-m", "local unmerged commit"])

        // Lock linkedLocked
        try git(mainRepo, ["worktree", "lock", "--reason", "WIP lock", linkedLocked.path])

        // Backdate clean worktree so it's not <1h recent
        let oldDate = Date().addingTimeInterval(-7200)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: linkedClean.path)

        let readPol = ReadAuthorizationPolicy(home: f.home.path, projectRoots: [devRoot.path], allowSystemLocations: false)
        let entries = WorktreeAndProjectDetector.scanWorktrees(
            authorizedRoots: [devRoot.path],
            readPolicy: readPol,
            checkActiveProcesses: false,
            now: Date()
        )

        let byPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.worktreePath, $0) })

        let cleanEntry = try XCTUnwrap(byPath[Paths.normalized(linkedClean.path)])
        XCTAssertTrue(cleanEntry.isLinkedWorktree)
        XCTAssertEqual(cleanEntry.status, .cleanIdle)
        XCTAssertEqual(cleanEntry.integrationEvidence, .mergedIntoDefaultBranch)
        XCTAssertTrue(cleanEntry.inventoryOnly)
        XCTAssertFalse(cleanEntry.selectionAllowed)

        let dirtyEntry = try XCTUnwrap(byPath[Paths.normalized(linkedDirty.path)])
        XCTAssertEqual(dirtyEntry.status, .dirtyUncommitted)
        XCTAssertEqual(dirtyEntry.dirtyCount, 1)

        let unpushedEntry = try XCTUnwrap(byPath[Paths.normalized(linkedUnpushed.path)])
        XCTAssertEqual(unpushedEntry.status, .unpushedCommits)
        XCTAssertEqual(unpushedEntry.integrationEvidence, .notMergedIntoDefaultBranch)

        let lockedEntry = try XCTUnwrap(byPath[Paths.normalized(linkedLocked.path)])
        XCTAssertEqual(lockedEntry.status, .locked)
        XCTAssertTrue(lockedEntry.isLocked)

        // Verify that a failed git command reports `inspectionFailedUnknown`, never `cleanIdle`
        let failedEntries = WorktreeAndProjectDetector.inspectRepositoryWorktrees(
            repositoryPath: mainRepo.path,
            readPolicy: readPol,
            gitExecutable: "/nonexistent/git-binary",
            checkActiveProcesses: false
        )
        XCTAssertEqual(failedEntries.first?.status, .inspectionFailedUnknown)
    }

    func testProjectArtifactsDetectorChecksAnchorsTrackedFilesAndSymlinks() throws {
        let f = try Fixture()
        let devRoot = f.home.appendingPathComponent("Developer")
        let swiftProj = devRoot.appendingPathComponent("SwiftApp")
        let nodeProj = devRoot.appendingPathComponent("WebApp")
        let symlinkProj = devRoot.appendingPathComponent("SymlinkApp")

        try FileManager.default.createDirectory(at: swiftProj.appendingPathComponent(".build"), withIntermediateDirectories: true)
        try Data("// swift-tools-version: 5.9\n".utf8).write(to: swiftProj.appendingPathComponent("Package.swift"))
        try Data(repeating: 0x41, count: 8192).write(to: swiftProj.appendingPathComponent(".build/lib.o"))
        let oldDate = Date().addingTimeInterval(-7200)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: swiftProj.appendingPathComponent(".build").path)

        // Node project where `dist/bundle.js` is tracked by Git!
        try FileManager.default.createDirectory(at: nodeProj.appendingPathComponent("dist"), withIntermediateDirectories: true)
        try Data("{\"name\":\"webapp\"}\n".utf8).write(to: nodeProj.appendingPathComponent("package.json"))
        try Data("console.log(1);\n".utf8).write(to: nodeProj.appendingPathComponent("dist/bundle.js"))
        _ = try CommandRunner.run("/usr/bin/git", ["-C", nodeProj.path, "init", "--initial-branch=main"])
        _ = try CommandRunner.run("/usr/bin/git", ["-C", nodeProj.path, "add", "-f", "dist/bundle.js"])

        // Symlink project where `target` is a symlink
        try FileManager.default.createDirectory(at: symlinkProj, withIntermediateDirectories: true)
        try Data("[package]\nname = \"sym\"\n".utf8).write(to: symlinkProj.appendingPathComponent("Cargo.toml"))
        let externalTarget = f.home.appendingPathComponent("ExternalTarget")
        try FileManager.default.createDirectory(at: externalTarget, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: symlinkProj.appendingPathComponent("target"),
            withDestinationURL: externalTarget
        )

        let readPol = ReadAuthorizationPolicy(home: f.home.path, projectRoots: [devRoot.path], allowSystemLocations: false)
        let artifacts = WorktreeAndProjectDetector.scanProjectArtifacts(
            authorizedRoots: [devRoot.path],
            readPolicy: readPol,
            checkActiveProcesses: false,
            now: Date()
        )
        let byPath = Dictionary(uniqueKeysWithValues: artifacts.map { ($0.artifactPath, $0) })

        let swiftBuild = try XCTUnwrap(byPath[Paths.normalized(swiftProj.appendingPathComponent(".build").path)])
        XCTAssertEqual(swiftBuild.state, .anchoredIdleCandidate)
        XCTAssertEqual(swiftBuild.anchorFile, "Package.swift")
        XCTAssertTrue(swiftBuild.inventoryOnly)
        XCTAssertFalse(swiftBuild.selectionAllowed)

        let trackedDist = try XCTUnwrap(byPath[Paths.normalized(nodeProj.appendingPathComponent("dist").path)])
        XCTAssertEqual(trackedDist.state, .blockedTrackedByGit, "Git-tracked files inside dist must block the artifact")
        XCTAssertEqual(trackedDist.trackedFileCount, 1)

        let symlinkTarget = try XCTUnwrap(byPath[Paths.normalized(symlinkProj.appendingPathComponent("target").path)])
        XCTAssertEqual(symlinkTarget.state, .blockedContainsSymlink)
        XCTAssertTrue(symlinkTarget.containsSymlink)
    }

    // MARK: - 3. SystemDiagnostics Tests

    func testSystemDiagnosticsSwapMemoryPressureAndSnapshotsParsing() throws {
        // 1. Live swap & memory pressure via Darwin sysctlbyname
        let liveSwap = SystemDiagnostics.sampleSwap()
        XCTAssertEqual(liveSwap.status, .available)
        XCTAssertNotNil(liveSwap.totalBytes)
        XCTAssertNotNil(liveSwap.usedBytes)
        XCTAssertFalse(liveSwap.includedInReclaimableSpace)

        let parsedSwap = try XCTUnwrap(
            SystemDiagnostics.parseSwapUsageString("total = 2048.00M  used = 512.00M  free = 1536.00M  (encrypted)")
        )
        XCTAssertEqual(parsedSwap.status, .available)
        XCTAssertEqual(parsedSwap.totalBytes, 2048 * 1024 * 1024)
        XCTAssertEqual(parsedSwap.usedBytes, 512 * 1024 * 1024)
        XCTAssertEqual(parsedSwap.freeBytes, 1536 * 1024 * 1024)
        XCTAssertEqual(parsedSwap.encrypted, true)
        XCTAssertFalse(parsedSwap.includedInReclaimableSpace)

        // 2. Memory pressure
        let livePressure = SystemDiagnostics.sampleMemoryPressure()
        XCTAssertEqual(livePressure.status, .available)
        XCTAssertNotEqual(livePressure.level, .unknown)
        XCTAssertNotNil(livePressure.compressedBytes)
        XCTAssertEqual(SystemDiagnostics.mapKernelPressureLevel(1), .normal)
        XCTAssertEqual(SystemDiagnostics.mapKernelPressureLevel(2), .warning)
        XCTAssertEqual(SystemDiagnostics.mapKernelPressureLevel(4), .critical)

        // 3. Local APFS snapshots parser
        let sampleTmutilOutput = """
        Snapshots for disk /:
        com.apple.TimeMachine.2026-11-12-100000.local
        com.apple.TimeMachine.2026-11-12-110000.local
        com.apple.os.update-MSUPrepareUpdate
        """
        let snapDiag = SystemDiagnostics.parseTmutilLocalSnapshots(sampleTmutilOutput)
        XCTAssertEqual(snapDiag.status, .available)
        XCTAssertEqual(snapDiag.totalCount, 3)
        XCTAssertEqual(snapDiag.timeMachineCount, 2)
        XCTAssertEqual(snapDiag.osUpdateCount, 1)
        XCTAssertFalse(snapDiag.includedInReclaimableSpace)
    }

    // MARK: - 4. SpaceMapBuilder & 0 B Sparse File Invariants

    func testSpaceMapMatchesSnapshotAllocatedBytesIDsAndZeroAllocatedSparseFile() throws {
        var files: [IndexedFile] = []
        let now = Date()

        // Create 10 synthetic indexed items across categories, including a 0 B allocated sparse file
        for i in 1...9 {
            let alloc = Int64(i * 1_048_576)
            files.append(
                IndexedFile(
                    id: "item-\(i)",
                    path: "/Users/test/Library/Caches/item-\(i).cache",
                    root: "/Users/test/Library/Caches",
                    identity: FileIdentity(device: 1, inode: UInt64(i), size: alloc, modified: 1, changed: 1),
                    allocatedBytes: alloc,
                    category: .cache,
                    modifiedAt: now,
                    eligible: true,
                    reason: "old_known_extension",
                    confidence: "high",
                    storageCategory: .appCaches,
                    titleES: "Elemento \(i)",
                    titleEN: "Item \(i)",
                    logicalBytes: alloc,
                    reclaimableBytes: alloc,
                    isPartial: (i == 9),
                    partialReason: (i == 9) ? "truncated_at_budget" : nil
                )
            )
        }

        // Item 10: 0 B allocated sparse file with 500 MB logical size
        let sparseFile = IndexedFile(
            id: "sparse-zero",
            path: "/Users/test/Library/Containers/com.docker.docker/Data/vms/0/data/sparse.raw",
            root: "/Users/test",
            identity: FileIdentity(device: 1, inode: 999, size: 500 * 1_048_576, modified: 1, changed: 1),
            allocatedBytes: 0,
            category: .other,
            modifiedAt: now,
            eligible: false,
            reason: "list_only_inventory",
            confidence: "high",
            storageCategory: .vmContainers,
            titleES: "Disco disperso 0 B",
            titleEN: "0 B sparse disk",
            logicalBytes: 500 * 1_048_576,
            virtualCapacityBytes: 500 * 1_048_576,
            reclaimableBytes: 0,
            inventoryOnly: true,
            selectionAllowed: false,
            cleanupEligibility: .inventoryOnly
        )
        files.append(sparseFile)

        var scan = ScanResult()
        scan.files = files
        scan.complete = false
        scan.rebuildCategoryAggregates()

        // 1. Category slice for .appCaches with maxVisibleTiles = 5 (4 top tiles + 1 "Otros" bucket)
        let cacheSlice = SpaceMapBuilder.build(from: scan, category: .appCaches, maxVisibleTiles: 5)
        let expectedCacheAllocated = files.filter { $0.storageCategory == .appCaches }.reduce(Int64(0)) { $0 + $1.allocatedBytes }
        XCTAssertEqual(cacheSlice.totalAllocatedBytes, expectedCacheAllocated)
        XCTAssertEqual(cacheSlice.tiles.count, 5)
        XCTAssertTrue(cacheSlice.tiles.last?.isOthersBucket == true, "5th tile must be the 'Otros' bucket")
        XCTAssertEqual(
            cacheSlice.tiles.reduce(Int64(0)) { $0 + $1.allocatedBytes },
            expectedCacheAllocated,
            "Sum of tiles (including 'Otros') must equal exact category allocatedBytes"
        )
        XCTAssertEqual(
            Set(cacheSlice.tiles.flatMap(\.groupedFileIDs)),
            Set(files.filter { $0.storageCategory == .appCaches }.map(\.id)),
            "SpaceMap tiles must account for every single IndexedFile.id in the category"
        )
        XCTAssertTrue(cacheSlice.isPartial, "Partial item must propagate partiality to SpaceMapSlice")

        // 2. Category slice for .vmContainers with 0 B allocated sparse file
        let vmSlice = SpaceMapBuilder.build(from: scan, category: .vmContainers, maxVisibleTiles: 8)
        XCTAssertEqual(vmSlice.totalAllocatedBytes, 0, "0 B allocated sparse file must NOT substitute logicalBytes into totalAllocatedBytes")
        XCTAssertEqual(vmSlice.totalLogicalBytes, 500 * 1_048_576)
        let vmTile = try XCTUnwrap(vmSlice.tiles.first)
        XCTAssertEqual(vmTile.id, "sparse-zero")
        XCTAssertEqual(vmTile.allocatedBytes, 0)
        XCTAssertEqual(vmTile.logicalBytes, 500 * 1_048_576)
        XCTAssertTrue(vmTile.isZeroAllocatedSparse)
    }

    // MARK: - 5. Disk Jockey Catalog Provenance Tests

    func testDiskJockeyProvenanceAndInventoryGuaranteesInCatalog() throws {
        let loaded = try CatalogLoader.load()
        XCTAssertEqual(loaded.catalog.rules.count, 399, "Primary Levo reference rule count must remain 399")
        XCTAssertEqual(loaded.catalog.diskJockeyRules.count, 10, "10 complementary Disk Jockey rules must be loaded")
        XCTAssertEqual(loaded.catalog.allRules.count, 409)

        // Every new Disk Jockey rule must carry upstreamProvenance and stay in inventory mode (listOnly: true)
        for rule in loaded.catalog.diskJockeyRules {
            let prov = try XCTUnwrap(rule.upstreamProvenance, "Missing upstreamProvenance on \(rule.id)")
            XCTAssertEqual(prov.repository, "https://github.com/bmcreations/disk-jockey")
            XCTAssertEqual(prov.commit, "f28f7e1914dcc74d7c29b0cebda516fb9394ba20")
            XCTAssertEqual(prov.license, "MIT")
            XCTAssertTrue(rule.listOnly, "Disk Jockey rule \(rule.id) must default to inventory mode (listOnly: true)")
        }

        // Overlapping rules must also carry upstreamProvenance
        let rulesWithProvenance = loaded.catalog.allRules.filter { $0.upstreamProvenance != nil }
        XCTAssertGreaterThanOrEqual(rulesWithProvenance.count, 75)
    }
}
