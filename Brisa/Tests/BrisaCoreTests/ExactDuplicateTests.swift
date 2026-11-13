import XCTest
import Darwin
@testable import BrisaCore

final class ExactDuplicateTests: XCTestCase {
    func testProgressiveScanMatchesContentRegardlessOfNameExcludesHardlinksSymlinksAndApps() throws {
        let f = try Fixture()
        let scanRoot = f.home.appendingPathComponent("Work/DupTest", isDirectory: true)
        let dirA = scanRoot.appendingPathComponent("A", isDirectory: true)
        let dirB = scanRoot.appendingPathComponent("B", isDirectory: true)
        let appDir = scanRoot.appendingPathComponent("Demo.app/Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        // > 64 KiB payload to exercise preliminary partial-compare stage + streaming SHA-256
        var payload = Data(repeating: 0x41, count: 140_000)
        payload[70_000] = 0x7A
        let orig = dirA.appendingPathComponent("original-video.bin")
        let dupDifferentName = dirB.appendingPathComponent("copied-name.bin")
        try payload.write(to: orig)
        try payload.write(to: dupDifferentName)

        // Same filename `report.txt` with DIFFERENT content -> must NOT match
        try Data("version one content".utf8).write(to: dirA.appendingPathComponent("report.txt"))
        try Data("version two content".utf8).write(to: dirB.appendingPathComponent("report.txt"))

        // Hardlink to `orig` -> must NOT be counted as an independent duplicate copy
        let hardlink = dirB.appendingPathComponent("hardlink.bin")
        XCTAssertEqual(Darwin.link(orig.path, hardlink.path), 0)

        // Symlink to `orig` -> must be excluded
        let symlink = dirB.appendingPathComponent("symlink.bin")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: orig)

        // Same payload inside a `.app` bundle -> excluded
        try payload.write(to: appDir.appendingPathComponent("bundled.bin"))

        let scope = DuplicateScopePolicy(home: f.home.path, authorizedFolders: [scanRoot.path])
        let report = ExactDuplicateScanner.scan(scope: scope)

        XCTAssertFalse(report.cancelled)
        XCTAssertEqual(report.groups.count, 1)
        let group = try XCTUnwrap(report.groups.first)
        XCTAssertEqual(group.files.count, 2, "Hardlink, symlink, and app bundle copy must not inflate copy count")
        XCTAssertEqual(Set(group.files.map(\.path)), Set([Paths.normalized(orig.path), Paths.normalized(dupDifferentName.path)]))
        XCTAssertGreaterThanOrEqual(report.skippedHardlinksCount, 1)
        XCTAssertGreaterThanOrEqual(report.skippedSymlinksCount, 1)
        XCTAssertGreaterThanOrEqual(report.skippedPackagesCount, 1)
    }

    func testKeptCopyModificationAndSurplusModificationAbortSafely() throws {
        let f = try Fixture()
        let folder = f.home.appendingPathComponent("Downloads/Check", isDirectory: true)
        let trashDir = f.home.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)

        let bytes = Data("exact-duplicate-content-payload-12345".utf8)
        let kept = folder.appendingPathComponent("kept.txt")
        let surplus1 = folder.appendingPathComponent("surplus1.txt")
        let surplus2 = folder.appendingPathComponent("surplus2.txt")
        try bytes.write(to: kept)
        try bytes.write(to: surplus1)
        try bytes.write(to: surplus2)

        let oldDate = Date().addingTimeInterval(-3600)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: kept.path)

        let scope = DuplicateScopePolicy(home: f.home.path, authorizedFolders: [folder.path])
        let scanReport = ExactDuplicateScanner.scan(scope: scope)
        let group = try XCTUnwrap(scanReport.groups.first)
        XCTAssertEqual(group.files.count, 3)

        let journal = Journal(store: try f.store())
        let cleaner = DuplicateCleaner(journal: journal, scope: scope, home: f.home.path, mover: ControlledTrash(directory: trashDir))

        // Selecting all 3 copies must be blocked by plan validation
        let allSelectedPlan = cleaner.buildPlan(selections: [
            DuplicateGroupSelection(group: group, protectedFilePath: kept.path, surplusFilePaths: group.files.map(\.path))
        ])
        XCTAssertEqual(allSelectedPlan.actionableResources.count, 2, "Protected copy excluded from surplus targets")

        // Mutate surplus1 to different content of SAME byte length -> must be rejected at execution!
        let sameLenTamper = Data("EXACT-duplicate-content-payload-12345".utf8)
        XCTAssertEqual(sameLenTamper.count, bytes.count)
        try sameLenTamper.write(to: surplus1)

        let plan = cleaner.buildPlan(selections: [
            DuplicateGroupSelection(group: group, protectedFilePath: kept.path, surplusFilePaths: [surplus1.path, surplus2.path])
        ])
        XCTAssertTrue(plan.canExecute)

        let result1 = try cleaner.execute(plan: plan, selections: [
            DuplicateGroupSelection(group: group, protectedFilePath: kept.path, surplusFilePaths: [surplus1.path, surplus2.path])
        ])
        XCTAssertEqual(result1.outcome, .partial)
        XCTAssertEqual(result1.rejectedItems, [Paths.normalized(surplus1.path)])
        XCTAssertEqual(result1.completedItems, [Paths.normalized(surplus2.path)])
        XCTAssertTrue(FileManager.default.fileExists(atPath: surplus1.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: surplus2.path))

        // Now recreate surplus2 and corrupt the KEPT protected copy before acting -> whole group rejected!
        try bytes.write(to: surplus2)
        let scanReport2 = ExactDuplicateScanner.scan(scope: scope)
        let group2 = try XCTUnwrap(scanReport2.groups.first)
        let keptEntry = try XCTUnwrap(group2.files.first { $0.path == Paths.normalized(kept.path) })
        let surplusEntry = try XCTUnwrap(group2.files.first { $0.path != keptEntry.path })

        let plan2 = cleaner.buildPlan(selections: [
            DuplicateGroupSelection(group: group2, protectedFilePath: keptEntry.path, surplusFilePaths: [surplusEntry.path])
        ])
        try Data("TAMPERED-kept-copy-content-payload!!".utf8).write(to: kept)

        let result2 = try cleaner.execute(plan: plan2, selections: [
            DuplicateGroupSelection(group: group2, protectedFilePath: keptEntry.path, surplusFilePaths: [surplusEntry.path])
        ])
        XCTAssertEqual(result2.outcome, .rejected)
        XCTAssertTrue(result2.completedItems.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: surplusEntry.path))
    }

    func testScopePolicyRejectsRootHomeAndSensitiveDirectories() throws {
        let f = try Fixture()
        let sshDir = f.home.appendingPathComponent(".ssh", isDirectory: true)
        try FileManager.default.createDirectory(at: sshDir, withIntermediateDirectories: true)

        let scope = DuplicateScopePolicy(home: f.home.path, authorizedFolders: ["/", f.home.path, sshDir.path, "/System"])
        XCTAssertFalse(scope.validateFolder("/").allowed)
        XCTAssertFalse(scope.validateFolder(f.home.path).allowed)
        XCTAssertFalse(scope.validateFolder(sshDir.path).allowed)
        XCTAssertFalse(scope.validateFolder("/System").allowed)

        let report = ExactDuplicateScanner.scan(scope: scope)
        XCTAssertTrue(report.scannedFolders.isEmpty)
        XCTAssertEqual(report.rejectedFolders.count, 4)
    }

    func testAPFSClonePhysicalExtentDistinguishesSelectedVsReclaimedBytes() throws {
        let f = try Fixture()
        let folder = f.home.appendingPathComponent("Media/Clones", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let original = folder.appendingPathComponent("large-a.bin")
        let clone = folder.appendingPathComponent("large-clone.bin")
        try Data(repeating: 0x5A, count: 131_072).write(to: original)

        // Attempt APFS copy-on-write clone on temp volume if supported
        let clonedOK = clonefile(original.path, clone.path, 0) == 0
        guard clonedOK else { return }

        let scope = DuplicateScopePolicy(home: f.home.path, authorizedFolders: [folder.path])
        let report = ExactDuplicateScanner.scan(scope: scope)
        let group = try XCTUnwrap(report.groups.first)
        XCTAssertEqual(group.files.count, 2)

        if group.likelyContainsAPFSClones {
            let cleaner = DuplicateCleaner(journal: Journal(store: try f.store()), scope: scope, home: f.home.path)
            let plan = cleaner.buildPlan(selections: [
                DuplicateGroupSelection(group: group, protectedFilePath: group.suggestedProtectedPath, surplusFilePaths: [group.files.last!.path])
            ])
            XCTAssertEqual(plan.totalBytes, 0, "APFS clone sharing blocks with kept copy frees ~0 data bytes")
            XCTAssertGreaterThan(plan.affectedResources.first?.sizeBytes ?? 0, 0)
        }
    }
}
