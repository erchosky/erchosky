import XCTest
import Darwin
@testable import BrisaCore

final class ProjectArtifactCleanupTests: XCTestCase {
    func testGroupingBlockingAndCleanTrashWithPreservedSourcesAndManifests() throws {
        let f = try Fixture()
        let devRoot = f.home.appendingPathComponent("Developer", isDirectory: true)
        let swiftProj = devRoot.appendingPathComponent("SwiftApp", isDirectory: true)
        let webProj = devRoot.appendingPathComponent("WebApp", isDirectory: true)
        let trashDir = f.home.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)

        // 1. SwiftPM project with cleanable `.build` and preserved `Package.swift`, `Sources/main.swift`, `.git`
        let buildDir = swiftProj.appendingPathComponent(".build", isDirectory: true)
        let sourcesDir = swiftProj.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        try Data("// swift-tools-version: 5.9\n".utf8).write(to: swiftProj.appendingPathComponent("Package.swift"))
        try Data("{}".utf8).write(to: swiftProj.appendingPathComponent("Package.resolved"))
        try Data("print(\"ok\")\n".utf8).write(to: sourcesDir.appendingPathComponent("main.swift"))
        try Data(repeating: 0x41, count: 16_384).write(to: buildDir.appendingPathComponent("object.o"))

        let oldDate = Date().addingTimeInterval(-7200)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: buildDir.appendingPathComponent("object.o").path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: buildDir.path)

        // 2. Web project with cleanable `node_modules` AND blocked Git-tracked `dist` AND nested subrepo `.next`
        let nmDir = webProj.appendingPathComponent("node_modules/pkg", isDirectory: true)
        let distDir = webProj.appendingPathComponent("dist", isDirectory: true)
        let nextSubrepo = webProj.appendingPathComponent(".next/.git", isDirectory: true)
        try FileManager.default.createDirectory(at: nmDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: distDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nextSubrepo, withIntermediateDirectories: true)
        try Data("{\"name\":\"webapp\"}\n".utf8).write(to: webProj.appendingPathComponent("package.json"))
        try Data("{}".utf8).write(to: webProj.appendingPathComponent("package-lock.json"))
        try Data(repeating: 0x42, count: 8_192).write(to: nmDir.deletingLastPathComponent().appendingPathComponent("pkg/index.js"))
        try Data("console.log('tracked')\n".utf8).write(to: distDir.appendingPathComponent("bundle.js"))
        try Data("x".utf8).write(to: webProj.appendingPathComponent(".next/build-manifest.json"))

        let initRes = try CommandRunner.run("/usr/bin/git", ["-C", webProj.path, "init", "--initial-branch=main"])
        XCTAssertEqual(initRes.status, 0)
        let addRes = try CommandRunner.run("/usr/bin/git", ["-C", webProj.path, "add", "-f", "package.json", "dist/bundle.js"])
        XCTAssertEqual(addRes.status, 0)

        for path in [
            nmDir.appendingPathComponent("index.js").path,
            webProj.appendingPathComponent("node_modules").path,
            webProj.appendingPathComponent(".next/build-manifest.json").path,
            webProj.appendingPathComponent(".next").path,
            distDir.appendingPathComponent("bundle.js").path,
            distDir.path
        ] {
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: path)
        }

        let readPol = ReadAuthorizationPolicy(home: f.home.path, projectRoots: [devRoot.path], allowSystemLocations: false)
        let policy = ProjectArtifactCleanupPolicy(home: f.home.path, readPolicy: readPol, checkActiveProcesses: true)
        let journal = Journal(store: try f.store())
        let cleaner = ProjectArtifactCleaner(journal: journal, policy: policy, mover: ControlledTrash(directory: trashDir))

        let groups = cleaner.scanGroups(authorizedRoots: [devRoot.path])
        XCTAssertEqual(groups.count, 2)

        let swiftGroup = try XCTUnwrap(groups.first { $0.projectRoot == Paths.normalized(swiftProj.path) })
        XCTAssertEqual(swiftGroup.projectName, "SwiftApp")
        XCTAssertEqual(swiftGroup.cleanableCount, 1)
        XCTAssertTrue(swiftGroup.preservedProjectFiles.contains("Package.swift"))
        XCTAssertTrue(swiftGroup.preservedProjectFiles.contains("Sources"))

        let webGroup = try XCTUnwrap(groups.first { $0.projectRoot == Paths.normalized(webProj.path) })
        XCTAssertEqual(webGroup.cleanableCount, 1)
        XCTAssertEqual(webGroup.blockedCount, 2)
        XCTAssertTrue(webGroup.preservedProjectFiles.contains(".git"))
        XCTAssertTrue(webGroup.preservedProjectFiles.contains("package-lock.json"))

        let allArtifacts = groups.flatMap(\.artifacts)
        let nmArtifact = try XCTUnwrap(allArtifacts.first { $0.artifactName == "node_modules" })
        let distArtifact = try XCTUnwrap(allArtifacts.first { $0.artifactName == "dist" })
        let nextArtifact = try XCTUnwrap(allArtifacts.first { $0.artifactName == ".next" })
        let swiftBuild = try XCTUnwrap(allArtifacts.first { $0.artifactName == ".build" })

        XCTAssertTrue(policy.evaluate(swiftBuild).allowed)
        XCTAssertNotNil(swiftBuild.modifiedAt)
        XCTAssertFalse(swiftBuild.rebuildCommand.isEmpty)
        XCTAssertFalse(swiftBuild.usageUncertaintyEN.isEmpty)
        XCTAssertTrue(policy.evaluate(nmArtifact).allowed)
        XCTAssertFalse(policy.evaluate(distArtifact).allowed)
        XCTAssertEqual(distArtifact.state, .blockedTrackedByGit)
        XCTAssertFalse(policy.evaluate(nextArtifact).allowed)
        XCTAssertEqual(nextArtifact.state, .blockedNestedSubrepository)

        // Build plan selecting both cleanable and blocked items: only eligible ones become actionable
        let plan = policy.buildPlan(selectedArtifacts: [swiftBuild, nmArtifact, distArtifact])
        XCTAssertTrue(plan.canExecute)
        XCTAssertEqual(plan.actionableResources.count, 2)
        XCTAssertEqual(plan.blockedResources.count, 1)
        XCTAssertEqual(plan.mechanism, .trash)
        XCTAssertEqual(plan.restorability, .trashRestore)
        XCTAssertEqual(plan.sizeBasis, .measured)
        XCTAssertTrue(plan.preservedSummaryEN.contains("Package.swift"))

        let report = try cleaner.execute(plan: plan, targets: [swiftBuild, nmArtifact, distArtifact])
        XCTAssertEqual(report.outcome, .completed)
        XCTAssertEqual(report.completedItems.count, 2)
        XCTAssertTrue(report.restorable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: buildDir.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: webProj.appendingPathComponent("node_modules").path))

        // Preserved files & blocked Git-tracked `dist` must still exist intact!
        XCTAssertTrue(FileManager.default.fileExists(atPath: swiftProj.appendingPathComponent("Package.swift").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourcesDir.appendingPathComponent("main.swift").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: webProj.appendingPathComponent("package.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: distDir.appendingPathComponent("bundle.js").path))

        let journalEntries = try journal.entries()
        XCTAssertTrue(journalEntries.contains { $0.id == "plan-\(plan.id)" && $0.status == "completed" && $0.mechanism == "trash" && $0.restorable == true })
        XCTAssertEqual(journalEntries.filter { $0.status == "trashed" }.count, 2)
    }

    func testActiveOpenFileDuringExecutionRejectsMoveOnRevalidation() throws {
        let f = try Fixture()
        let project = f.home.appendingPathComponent("Developer/OpenBuild", isDirectory: true)
        let buildDir = project.appendingPathComponent(".build", isDirectory: true)
        let trashDir = f.home.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        try Data("// swift-tools-version: 5.9\n".utf8).write(to: project.appendingPathComponent("Package.swift"))
        let obj = buildDir.appendingPathComponent("artifact.o")
        try Data(repeating: 0x55, count: 4_096).write(to: obj)
        let oldDate = Date().addingTimeInterval(-7200)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: obj.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: buildDir.path)

        let readPol = ReadAuthorizationPolicy(home: f.home.path, projectRoots: [project.deletingLastPathComponent().path], allowSystemLocations: false)
        let policy = ProjectArtifactCleanupPolicy(home: f.home.path, readPolicy: readPol, checkActiveProcesses: true)
        let cleaner = ProjectArtifactCleaner(journal: Journal(store: try f.store()), policy: policy, mover: ControlledTrash(directory: trashDir))

        let groups = cleaner.scanGroups(authorizedRoots: [project.deletingLastPathComponent().path])
        let entry = try XCTUnwrap(groups.first?.artifacts.first)
        let plan = policy.buildPlan(selectedArtifacts: [entry])
        XCTAssertTrue(plan.canExecute)

        // Hold open descriptor inside artifact directory between plan and execution
        let fd = Darwin.open(obj.path, O_RDONLY)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }

        let report = try cleaner.execute(plan: plan, targets: [entry])
        XCTAssertEqual(report.outcome, .rejected)
        XCTAssertTrue(report.completedItems.isEmpty)
        XCTAssertEqual(report.rejectedItems, [entry.artifactPath])
        XCTAssertTrue(FileManager.default.fileExists(atPath: buildDir.path))
    }

    func testCancellationMidBatchRecordsPartialWithoutFalseRollback() throws {
        struct CancellingMover: TrashMoving {
            let inner: TrashMoving
            let flag: CancellationFlag
            func move(_ url: URL) throws -> URL? {
                let res = try inner.move(url)
                flag.cancel()
                return res
            }
        }

        let f = try Fixture()
        let devRoot = f.home.appendingPathComponent("Developer", isDirectory: true)
        let p1 = devRoot.appendingPathComponent("Alpha", isDirectory: true)
        let p2 = devRoot.appendingPathComponent("Beta", isDirectory: true)
        let trashDir = f.home.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)

        let oldDate = Date().addingTimeInterval(-7200)
        for p in [p1, p2] {
            let b = p.appendingPathComponent(".build", isDirectory: true)
            try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
            try Data("// swift-tools-version: 5.9\n".utf8).write(to: p.appendingPathComponent("Package.swift"))
            let o = b.appendingPathComponent("a.o")
            try Data(repeating: 0x33, count: 4096).write(to: o)
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: o.path)
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: b.path)
        }

        let readPol = ReadAuthorizationPolicy(home: f.home.path, projectRoots: [devRoot.path], allowSystemLocations: false)
        let policy = ProjectArtifactCleanupPolicy(home: f.home.path, readPolicy: readPol, checkActiveProcesses: false)
        let journal = Journal(store: try f.store())
        let flag = CancellationFlag()
        let cleaner = ProjectArtifactCleaner(
            journal: journal,
            policy: policy,
            mover: CancellingMover(inner: ControlledTrash(directory: trashDir), flag: flag)
        )
        let entries = cleaner.scanGroups(authorizedRoots: [devRoot.path]).flatMap(\.artifacts)
        let plan = policy.buildPlan(selectedArtifacts: entries)

        let report = try cleaner.execute(plan: plan, targets: entries, cancellation: flag)
        XCTAssertEqual(report.outcome, .partial)
        XCTAssertEqual(report.completedItems.count, 1)
        XCTAssertEqual(report.skippedOnCancellation.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: entries[0].artifactPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: entries[1].artifactPath))

        let jEntries = try journal.entries()
        let planEntry = try XCTUnwrap(jEntries.first { $0.id == "plan-\(plan.id)" })
        XCTAssertEqual(planEntry.status, "partial")
        XCTAssertTrue(planEntry.detailNote?.contains("not rolled back") == true)
        XCTAssertEqual(jEntries.filter { $0.status == "trashed" }.count, 1)
    }

    func testRejectsUnverifiedOriginAndRecentChildWrites() throws {
        let f = try Fixture()
        let devRoot = f.home.appendingPathComponent("Developer", isDirectory: true)
        let proj = devRoot.appendingPathComponent("RecentProj", isDirectory: true)
        let target = proj.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("[package]\nname = \"demo\"\n".utf8).write(to: proj.appendingPathComponent("Cargo.toml"))
        let rlib = target.appendingPathComponent("libdemo.rlib")
        try Data(repeating: 0x22, count: 4096).write(to: rlib)
        // Parent older than 2 hours, but inner file written 10 seconds ago
        let oldDate = Date().addingTimeInterval(-7200)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-10)], ofItemAtPath: rlib.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: target.path)

        let readPol = ReadAuthorizationPolicy(home: f.home.path, projectRoots: [devRoot.path], allowSystemLocations: false)
        let policy = ProjectArtifactCleanupPolicy(home: f.home.path, readPolicy: readPol, checkActiveProcesses: false)
        let cleaner = ProjectArtifactCleaner(journal: Journal(store: try f.store()), policy: policy, mover: ControlledTrash(directory: f.home))

        let entry = try XCTUnwrap(cleaner.scanGroups(authorizedRoots: [devRoot.path]).first?.artifacts.first)
        let decision = policy.evaluate(entry)
        XCTAssertFalse(decision.allowed, "Recent child write within 5 minutes must block cleanup")

        // Missing git executable must remain unverified/blocked
        let badGit = WorktreeAndProjectDetector.inspectSingleProjectArtifact(
            artifactPath: target.path,
            artifactName: "target",
            projectRoot: proj.path,
            anchorFile: "Cargo.toml",
            ecosystem: "Rust / Maven",
            readPolicy: readPol,
            gitExecutable: "/nonexistent/git",
            checkActiveProcesses: false
        )
        XCTAssertEqual(badGit.state, .blockedUnverifiedGitOrUsage)
        XCTAssertFalse(policy.evaluate(badGit).allowed)
    }
}
