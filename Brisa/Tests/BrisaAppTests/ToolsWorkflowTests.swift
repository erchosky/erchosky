import XCTest
import AppKit
import SwiftUI
@testable import BrisaCore
@testable import BrisaApp

private final class MockWorkflowTrashMover: TrashMoving, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var movedPaths: [String] = []
    private let trashDir: URL

    init(trashDir: URL) {
        self.trashDir = trashDir
        try? FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
    }

    func move(_ url: URL) throws -> URL? {
        lock.lock()
        movedPaths.append(Paths.normalized(url.path))
        lock.unlock()
        let dest = trashDir.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.moveItem(at: url, to: dest)
        }
        return dest
    }
}

private final class MockWorkflowCommandExecutor: CommandExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var recordedRequests: [CommandExecutionRequest] = []
    private let handler: @Sendable (CommandExecutionRequest) throws -> CommandResult

    init(handler: @escaping @Sendable (CommandExecutionRequest) throws -> CommandResult) {
        self.handler = handler
    }

    func run(_ request: CommandExecutionRequest, control: ScanControl?) throws -> CommandResult {
        if let control, control.shouldStop {
            throw BrisaError.cancelled
        }
        lock.lock()
        recordedRequests.append(request)
        lock.unlock()
        return try handler(request)
    }
}

final class ToolsWorkflowTests: XCTestCase {
    @MainActor
    private func withSandboxState(
        executor: any CommandExecuting = LiveCommandExecutor(),
        trashMover: (any TrashMoving)? = nil,
        body: (AppState, URL, MockWorkflowTrashMover) async throws -> Void
    ) async throws {
        let resolvedTemp = try Paths.systemLocation(NSTemporaryDirectory())
        let sandbox = URL(fileURLWithPath: resolvedTemp)
            .appendingPathComponent("BrisaToolsFlow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sandbox,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let trashDir = sandbox.appendingPathComponent(".FakeTrash", isDirectory: true)
        let defaultMover = MockWorkflowTrashMover(trashDir: trashDir)
        let suite = "dev.brisa.toolsflow.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let previousLang = L10n.currentPreference
        defer { L10n.setPreference(previousLang) }

        let state = AppState(
            userDefaults: defaults,
            storeURL: sandbox.appendingPathComponent("State"),
            ipcSocketPath: nil,
            homeDirectory: sandbox.path,
            startServices: false,
            commandExecutor: executor,
            trashMover: trashMover ?? defaultMover
        )
        defer { state.shutdown() }
        try await body(state, sandbox, defaultMover)
    }

    @MainActor
    private func waitUntil(
        timeoutSeconds: TimeInterval = 5.0,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !condition() {
            if Date() >= deadline {
                XCTFail("Timed out waiting for async coordinator state")
                return
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    private func writeStubExecutable(at url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func makeMockPlistApp(at bundleURL: URL, bundleID: String, executableName: String = "DemoExec") throws {
        let macOSDir = bundleURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": bundleURL.deletingPathExtension().lastPathComponent,
            "CFBundleExecutable": executableName,
            "CFBundleVersion": "1.0"
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plistData.write(to: bundleURL.appendingPathComponent("Contents/Info.plist"))
        try "#!/bin/sh\necho ok\n".write(to: macOSDir.appendingPathComponent(executableName), atomically: true, encoding: .utf8)
    }

    func testToolsAndMenuBarLocalizationResolveWithoutRawKeysInESAndEN() {
        let prev = L10n.currentPreference
        defer { L10n.setPreference(prev) }

        for lang in ["es", "en"] {
            L10n.setPreference(lang)
            XCTAssertFalse(L10n.Common.navTools.contains("nav."))
            XCTAssertFalse(L10n.Common.journalPlanned.contains("journal."))
            XCTAssertFalse(L10n.Common.journalPartial.contains("journal."))
            XCTAssertFalse(L10n.MenuBar.navBack.contains("nav."))
            XCTAssertFalse(L10n.MenuBar.navToolsSection.contains("nav."))
            XCTAssertFalse(L10n.Tools.tabProjects.contains("tab."))
            XCTAssertFalse(L10n.Tools.tabPackages.contains("tab."))
            XCTAssertFalse(L10n.Tools.tabDuplicates.contains("tab."))
            XCTAssertFalse(L10n.Tools.tabDocker.contains("tab."))
            XCTAssertFalse(L10n.Tools.planHeader.contains("plan."))
            XCTAssertFalse(L10n.Activity.entryCounts(1, 2).contains("entry."))
        }
    }

    @MainActor
    func testMenuBarRouteStackTriStateCheckboxesAndLockedItemsStayInline() async throws {
        try await withSandboxState { state, sandbox, _ in
            var revealedWindow = false
            state.revealWindow = { revealedWindow = true }

            let file1 = IndexedFile(
                id: "cache-1",
                path: sandbox.appendingPathComponent("Library/Caches/com.example/one.cache").path,
                root: sandbox.appendingPathComponent("Library/Caches").path,
                identity: FileIdentity(device: 1, inode: 101, size: 4096, modified: 1, changed: 1),
                allocatedBytes: 4096,
                category: .cache,
                modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                eligible: true,
                reason: "eligible",
                confidence: "high",
                storageCategory: .appCaches,
                sourceGroup: "Example"
            )
            let file2 = IndexedFile(
                id: "cache-2",
                path: sandbox.appendingPathComponent("Library/Caches/com.example/two.cache").path,
                root: sandbox.appendingPathComponent("Library/Caches").path,
                identity: FileIdentity(device: 1, inode: 102, size: 8192, modified: 1, changed: 1),
                allocatedBytes: 8192,
                category: .cache,
                modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                eligible: true,
                reason: "eligible",
                confidence: "high",
                storageCategory: .appCaches,
                sourceGroup: "Example"
            )
            let locked = IndexedFile(
                id: "cache-locked",
                path: sandbox.appendingPathComponent("Library/Caches/com.example/in-use.cache").path,
                root: sandbox.appendingPathComponent("Library/Caches").path,
                identity: FileIdentity(device: 1, inode: 103, size: 2048, modified: 1, changed: 1),
                allocatedBytes: 2048,
                category: .cache,
                modifiedAt: Date(),
                eligible: false,
                reason: "protected",
                confidence: "protected",
                storageCategory: .appCaches,
                sourceGroup: "Example"
            )

            var scan = ScanResult()
            scan.files = [file1, file2, locked]
            scan.categories = [
                CategoryReport(
                    category: .appCaches,
                    status: .measured,
                    itemCount: 3,
                    eligibleCount: 2,
                    allocatedBytes: 14_336,
                    logicalBytes: 14_336,
                    reclaimableBytes: 12_288
                )
            ]
            scan.complete = true
            scan.finishedAt = Date()
            state.scan = scan

            XCTAssertEqual(state.tools.menuRoute, .home)
            state.tools.toggleExpandedMenuCategory(.appCaches)
            XCTAssertTrue(state.tools.expandedMenuCategories.contains(.appCaches))

            XCTAssertEqual(state.categorySelectionState(.appCaches), .unchecked)
            state.toggle(file1)
            XCTAssertEqual(state.categorySelectionState(.appCaches), .mixed)

            // Locked file must never become selectable.
            state.toggle(locked)
            XCTAssertFalse(state.selected.contains(locked.id))

            // Clicking category checkbox completes selection cleanly across eligible rows only.
            state.toggleCategorySelection(.appCaches)
            XCTAssertEqual(state.categorySelectionState(.appCaches), .checked)
            XCTAssertEqual(state.selected, Set(["cache-1", "cache-2"]))

            // Inline navigation preserves route history and never jumps to the main window.
            state.tools.pushMenuRoute(.category(.appCaches))
            XCTAssertEqual(state.tools.menuRoute, .category(.appCaches))
            state.tools.pushMenuRoute(.toolProjects)
            XCTAssertEqual(state.tools.menuRoute, .toolProjects)
            XCTAssertTrue(state.tools.expandedMenuCategories.contains(.appCaches))
            XCTAssertEqual(state.selected, Set(["cache-1", "cache-2"]))

            state.tools.popMenuRoute()
            XCTAssertEqual(state.tools.menuRoute, .category(.appCaches))
            state.tools.popMenuRoute()
            XCTAssertEqual(state.tools.menuRoute, .home)
            XCTAssertFalse(revealedWindow)

            state.toggleCategorySelection(.appCaches)
            XCTAssertEqual(state.categorySelectionState(.appCaches), .unchecked)
        }
    }

    @MainActor
    func testProjectArtifactsCoordinatorScansBlocksSymlinkAndExecutesToTrash() async throws {
        try await withSandboxState { state, sandbox, mover in
            let projectDir = sandbox.appendingPathComponent("Projects/SwiftSample", isDirectory: true)
            let buildDir = projectDir.appendingPathComponent(".build/debug", isDirectory: true)
            try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
            let artifactBin = buildDir.appendingPathComponent("artifact.bin")
            try Data(repeating: 0xAA, count: 4096).write(to: artifactBin)
            try "// pkg".write(to: projectDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
            let agedDate = Date().addingTimeInterval(-7200)
            for path in [artifactBin.path, buildDir.path, projectDir.appendingPathComponent(".build").path] {
                try FileManager.default.setAttributes([.modificationDate: agedDate], ofItemAtPath: path)
            }

            // Also include an isolated symlink artifact to confirm policy blocks it.
            let linkTarget = projectDir.appendingPathComponent("target")
            try FileManager.default.createSymbolicLink(atPath: linkTarget.path, withDestinationPath: buildDir.path)

            state.tools.addProjectRoot(url: sandbox.appendingPathComponent("Projects", isDirectory: true))
            state.tools.scanProjects()
            try await waitUntil { !state.tools.isScanningProjects && !state.tools.projectGroups.isEmpty }

            let artifacts = state.tools.projectGroups.flatMap(\.artifacts)
            let buildEntry = try XCTUnwrap(artifacts.first { $0.artifactName == ".build" })
            let policy = state.tools.projectPolicy()
            XCTAssertTrue(policy.evaluate(buildEntry).allowed)

            if let symlinkEntry = artifacts.first(where: { $0.artifactName == "target" }) {
                XCTAssertFalse(policy.evaluate(symlinkEntry).allowed)
                state.tools.toggleProjectArtifact(symlinkEntry, decision: policy.evaluate(symlinkEntry))
                XCTAssertFalse(state.tools.selectedProjectArtifactIDs.contains(symlinkEntry.id))
            }

            state.tools.toggleProjectArtifact(buildEntry, decision: policy.evaluate(buildEntry))
            XCTAssertTrue(state.tools.selectedProjectArtifactIDs.contains(buildEntry.id))

            state.tools.prepareProjectCleanupPlan(fromMenuBar: true)
            XCTAssertEqual(state.tools.menuRoute, .reviewPlan)
            let plan = try XCTUnwrap(state.tools.pendingPlanContext?.plan)
            XCTAssertEqual(plan.domain, .projectArtifacts)
            XCTAssertEqual(plan.mechanism, .trash)
            XCTAssertTrue(plan.canExecute)

            state.tools.executePendingPlan()
            try await waitUntil { !state.tools.isExecutingPlan && state.tools.lastExecutionReport != nil }

            let report = try XCTUnwrap(state.tools.lastExecutionReport)
            XCTAssertEqual(report.outcome, .completed)
            XCTAssertEqual(state.tools.menuRoute, .executionResult)
            XCTAssertEqual(mover.movedPaths, [Paths.normalized(buildEntry.artifactPath)])
            XCTAssertTrue(FileManager.default.fileExists(atPath: projectDir.appendingPathComponent("Package.swift").path))
            state.reloadJournalEntries()
            XCTAssertGreaterThanOrEqual(state.journalSummary.completedPlansCount, 1)
        }
    }

    @MainActor
    func testPackageManagersCoordinatorExecutesStructuredWholeCacheCleanup() async throws {
        let executor = MockWorkflowCommandExecutor { request in
            let cmd = URL(fileURLWithPath: request.executable).lastPathComponent
            let args = request.arguments
            switch (cmd, args) {
            case ("brew", ["--version"]):
                return CommandResult(status: 0, output: "Homebrew 4.5.0\n", error: "")
            case ("brew", ["--cache"]):
                return CommandResult(status: 0, output: "/tmp/brisa-mock-brew-cache\n", error: "")
            case ("brew", ["cleanup", "--dry-run"]):
                return CommandResult(status: 0, output: "Would remove: /tmp/brisa-mock-brew-cache/demo.tar.gz\n", error: "")
            case ("brew", ["cleanup", "-s", "--dry-run"]):
                return CommandResult(status: 0, output: "Would remove: /tmp/brisa-mock-brew-cache/demo.tar.gz\n", error: "")
            case ("brew", ["cleanup"]):
                return CommandResult(status: 0, output: "Removing cache...\n", error: "")
            case ("brew", ["cleanup", "-s"]):
                return CommandResult(status: 0, output: "Removing cache...\n", error: "")
            case ("npm", ["--version"]):
                return CommandResult(status: 0, output: "10.9.9\n", error: "")
            case ("npm", ["config", "get", "cache"]):
                return CommandResult(status: 0, output: "/tmp/brisa-mock-npm-cache\n", error: "")
            case ("npm", ["cache", "clean", "--force"]):
                return CommandResult(status: 0, output: "cache cleared\n", error: "")
            default:
                return CommandResult(status: 1, output: "", error: "not available")
            }
        }

        try await withSandboxState(executor: executor) { state, sandbox, _ in
            try writeStubExecutable(at: sandbox.appendingPathComponent(".local/bin/brew"))
            try writeStubExecutable(at: sandbox.appendingPathComponent(".local/bin/npm"))

            state.tools.scanPackageManagers()
            try await waitUntil { !state.tools.isScanningPackages && !state.tools.packageInspections.isEmpty }

            let brew = try XCTUnwrap(state.tools.packageInspections.first { $0.kind == .homebrew })
            XCTAssertTrue(brew.isInstalled)
            let cap = try XCTUnwrap(brew.capabilities.first(where: \.isAvailable))

            state.tools.preparePackageManagerPlan(inspection: brew, capability: cap, fromMenuBar: false)
            XCTAssertTrue(state.tools.showMenuPlanSheetInWindow)
            let plan = try XCTUnwrap(state.tools.pendingPlanContext?.plan)
            XCTAssertEqual(plan.domain, .packageManagers)
            XCTAssertEqual(plan.mechanism, .toolCommand)
            XCTAssertTrue(plan.canExecute)

            state.tools.executePendingPlan()
            try await waitUntil { !state.tools.isExecutingPlan && state.tools.lastExecutionReport != nil }
            let report = try XCTUnwrap(state.tools.lastExecutionReport)
            XCTAssertEqual(report.outcome, .completed)
            XCTAssertTrue(executor.recordedRequests.contains {
                URL(fileURLWithPath: $0.executable).lastPathComponent == "brew" &&
                ($0.arguments == ["cleanup"] || $0.arguments == ["cleanup", "-s"])
            })
        }
    }

    @MainActor
    func testExactDuplicatesCoordinatorProtectsOneCopyAndTrashesSurplus() async throws {
        try await withSandboxState { state, sandbox, mover in
            let scopeDir = sandbox.appendingPathComponent("DuplicateScope", isDirectory: true)
            let dirA = scopeDir.appendingPathComponent("A", isDirectory: true)
            let dirB = scopeDir.appendingPathComponent("B", isDirectory: true)
            try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)

            let payload = Data("exact-duplicate-content-payload-123456".utf8)
            let fileA = dirA.appendingPathComponent("copy.dat")
            let fileB = dirB.appendingPathComponent("renamed-copy.dat")
            let decoy = dirB.appendingPathComponent("copy.dat")
            try payload.write(to: fileA)
            try payload.write(to: fileB)
            try Data("different-name-same-name-different-bytes".utf8).write(to: decoy)

            // Reject outside-home / system root cleanly.
            state.tools.addDuplicateFolder(url: URL(fileURLWithPath: "/System", isDirectory: true))
            XCTAssertNotNil(state.tools.duplicatesError)
            XCTAssertTrue(state.tools.duplicateAuthorizedRoots.isEmpty)

            state.tools.addDuplicateFolder(url: scopeDir)
            XCTAssertNil(state.tools.duplicatesError)
            state.tools.scanDuplicates()
            try await waitUntil { !state.tools.isScanningDuplicates && state.tools.duplicateReport != nil }

            let report = try XCTUnwrap(state.tools.duplicateReport)
            XCTAssertEqual(report.groups.count, 1)
            let group = try XCTUnwrap(report.groups.first)

            // Explicitly keep fileA and mark fileB for removal.
            state.tools.setProtectedCopy(for: group, path: Paths.normalized(fileA.path))
            let entryB = try XCTUnwrap(group.files.first { $0.path == Paths.normalized(fileB.path) })
            state.tools.toggleDuplicateCopy(entryB, in: group)

            // Toggling the kept copy must be blocked.
            let entryA = try XCTUnwrap(group.files.first { $0.path == Paths.normalized(fileA.path) })
            state.tools.toggleDuplicateCopy(entryA, in: group)
            XCTAssertFalse(state.tools.duplicateSelectedDeletePaths.contains(entryA.path))

            let totals = state.tools.duplicateSelectionTotals()
            XCTAssertGreaterThan(totals.selectedBytes, 0)

            state.tools.prepareDuplicatesPlan(fromMenuBar: true)
            XCTAssertEqual(state.tools.menuRoute, .reviewPlan)
            state.tools.executePendingPlan()
            try await waitUntil { !state.tools.isExecutingPlan && state.tools.lastExecutionReport != nil }

            let execReport = try XCTUnwrap(state.tools.lastExecutionReport)
            XCTAssertEqual(execReport.outcome, .completed)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileA.path))
            XCTAssertEqual(mover.movedPaths, [Paths.normalized(fileB.path)])
        }
    }

    @MainActor
    func testAppUninstallerCoordinatorSeparatesExclusiveSharedAndTrashesSelection() async throws {
        try await withSandboxState { state, sandbox, mover in
            let appsDir = sandbox.appendingPathComponent("Applications", isDirectory: true)
            let demoAppURL = appsDir.appendingPathComponent("DemoApp.app", isDirectory: true)
            let companionAppURL = appsDir.appendingPathComponent("Companion.app", isDirectory: true)
            try makeMockPlistApp(at: demoAppURL, bundleID: "com.example.demo")
            try makeMockPlistApp(at: companionAppURL, bundleID: "com.example.companion")

            let demoInfoURL = demoAppURL.appendingPathComponent("Contents/Info.plist")
            let compInfoURL = companionAppURL.appendingPathComponent("Contents/Info.plist")
            let sharedGroups = ["group.example.shared"]
            for (plistURL, bid) in [(demoInfoURL, "com.example.demo"), (compInfoURL, "com.example.companion")] {
                let updated: [String: Any] = [
                    "CFBundleIdentifier": bid,
                    "CFBundleName": bid,
                    "CFBundleExecutable": "DemoExec",
                    "CFBundleVersion": "1.0",
                    "BrisaAppGroups": sharedGroups
                ]
                let data = try PropertyListSerialization.data(fromPropertyList: updated, format: .xml, options: 0)
                try data.write(to: plistURL)
            }

            let exclusiveCache = sandbox.appendingPathComponent("Library/Caches/com.example.demo", isDirectory: true)
            let sharedGroup = sandbox.appendingPathComponent("Library/Group Containers/group.example.shared", isDirectory: true)
            try FileManager.default.createDirectory(at: exclusiveCache, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: sharedGroup, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 512).write(to: exclusiveCache.appendingPathComponent("cache.db"))
            try Data(repeating: 2, count: 512).write(to: sharedGroup.appendingPathComponent("shared.db"))

            let demoItem = ApplicationItem(url: demoAppURL)
            let companionItem = ApplicationItem(url: companionAppURL)
            state.applications = [demoItem, companionItem]

            state.tools.inspectApplication(demoItem)
            try await waitUntil { !state.tools.isInspectingApp && state.tools.inspectedApp != nil }

            let inspection = try XCTUnwrap(state.tools.inspectedApp)
            XCTAssertTrue(inspection.relatedItems.contains { $0.tier == AppAssociationTier.exclusiveData && $0.defaultSelected })
            XCTAssertTrue(inspection.relatedItems.contains { $0.tier == AppAssociationTier.possibleShared && !$0.defaultSelected })

            state.tools.prepareUninstallPlan(fromMenuBar: false)
            let plan = try XCTUnwrap(state.tools.pendingPlanContext?.plan)
            XCTAssertEqual(plan.domain, .appUninstall)
            XCTAssertTrue(plan.canExecute)

            state.tools.executePendingPlan()
            try await waitUntil { !state.tools.isExecutingPlan && state.tools.lastExecutionReport != nil }

            let report = try XCTUnwrap(state.tools.lastExecutionReport)
            XCTAssertEqual(report.outcome, .completed)
            XCTAssertTrue(FileManager.default.fileExists(atPath: sharedGroup.path))
            XCTAssertTrue(mover.movedPaths.contains(Paths.normalized(exclusiveCache.path)))
        }
    }

    @MainActor
    func testDockerCoordinatorLocksVolumesByDefaultAndRecordsPartialOutcome() async throws {
        let executor = MockWorkflowCommandExecutor { request in
            let args = request.arguments
            if args == ["version", "--format", "{{.Client.Version}}"] {
                return CommandResult(status: 0, output: "29.0.0\n", error: "")
            }
            if args == ["info", "--format", "{{json .ServerVersion}}"] {
                return CommandResult(status: 0, output: "\"29.0.0\"\n", error: "")
            }
            if args == ["system", "df", "-v", "--format", "json"] {
                let dfv = """
                {"Images":[{"Repository":"alpine","Tag":"latest","ID":"111111111111","Size":"5MB","SharedSize":"2MB","UniqueSize":"3MB","Containers":"1"}],"Containers":[{"ID":"ctr1","Names":"stopped-job","State":"exited","Size":"1MB"}],"Volumes":[{"Name":"db-vol","Driver":"local","Scope":"local","Mountpoint":"/var/lib/docker/volumes/db-vol/_data","Links":"0","Size":"12MB"}]}
                """
                return CommandResult(status: 0, output: dfv, error: "")
            }
            if args == ["system", "df", "--format", "json"] {
                let df = """
                {"Type":"Images","TotalCount":"1","Active":"0","Size":"5MB","Reclaimable":"3MB"}
                {"Type":"Containers","TotalCount":"1","Active":"0","Size":"1MB","Reclaimable":"1MB"}
                {"Type":"Local Volumes","TotalCount":"1","Active":"0","Size":"12MB","Reclaimable":"12MB"}
                {"Type":"Build Cache","TotalCount":"1","Active":"0","Size":"4MB","Reclaimable":"4MB"}
                """
                return CommandResult(status: 0, output: df, error: "")
            }
            if args == ["ps", "-a", "--format", "json", "--no-trunc"] {
                return CommandResult(status: 0, output: #"{"ID":"ctr10000","Names":"stopped-job","Image":"alpine:latest","State":"exited","Status":"Exited (0)","Mounts":"","Size":"1MB"}"#, error: "")
            }
            if args.first == "inspect" && args.contains("--format") && args.contains("json") {
                return CommandResult(status: 0, output: #"[{"Id":"ctr10000","Name":"/stopped-job","Image":"sha256:111111111111","State":{"Running":false,"Status":"exited"},"Config":{"Image":"alpine:latest"},"Mounts":[]}]"#, error: "")
            }
            if args == ["inspect", "--format", "{{.State.Running}}", "ctr10000"] {
                return CommandResult(status: 0, output: "false\n", error: "")
            }
            if args == ["image", "ls", "--format", "json", "--no-trunc"] {
                return CommandResult(status: 0, output: #"{"ID":"sha256:1111111111110000","Repository":"alpine","Tag":"latest","Digest":"sha256:aaa","Size":"5MB","SharedSize":"N/A","UniqueSize":"N/A","Containers":"1"}"#, error: "")
            }
            if args == ["volume", "ls", "--format", "json"] {
                return CommandResult(status: 0, output: #"{"Name":"db-vol","Driver":"local","Scope":"local","Mountpoint":"/var/lib/docker/volumes/db-vol/_data","Labels":"","Links":"N/A","Size":"N/A"}"#, error: "")
            }
            if args == ["builder", "du", "--format", "json"] {
                return CommandResult(status: 0, output: #"{"ID":"bc1","Type":"regular","Description":"step","Size":"4MB","Shared":false,"Reclaimable":true,"Mutable":true,"UsageCount":1}"#, error: "")
            }
            if args == ["rm", "ctr10000"] {
                return CommandResult(status: 0, output: "ctr10000\n", error: "")
            }
            if args == ["volume", "rm", "db-vol"] {
                return CommandResult(status: 1, output: "", error: "volume remove failure simulated")
            }
            return CommandResult(status: 0, output: "", error: "")
        }

        try await withSandboxState(executor: executor) { state, sandbox, _ in
            try writeStubExecutable(at: sandbox.appendingPathComponent(".docker/bin/docker"))

            state.tools.inspectDocker()
            try await waitUntil { !state.tools.isInspectingDocker && state.tools.dockerSnapshot != nil }

            let snapshot = try XCTUnwrap(state.tools.dockerSnapshot)
            XCTAssertEqual(snapshot.status, .ready)
            let ctr = try XCTUnwrap(snapshot.stoppedContainers.first)
            let vol = try XCTUnwrap(snapshot.volumes.first)

            // Locked volume cannot be selected until explicitly unlocked.
            state.tools.toggleDockerVolumeSelection(vol)
            XCTAssertFalse(state.tools.selectedDockerVolumeNames.contains(vol.name))
            state.tools.toggleDockerVolumeLock(vol)
            state.tools.toggleDockerVolumeSelection(vol)
            XCTAssertTrue(state.tools.selectedDockerVolumeNames.contains(vol.name))
            state.tools.toggleDockerContainer(ctr)

            state.tools.prepareDockerPlan(fromMenuBar: true)
            XCTAssertEqual(state.tools.menuRoute, .reviewPlan)
            let plan = try XCTUnwrap(state.tools.pendingPlanContext?.plan)
            XCTAssertTrue(plan.requiresExplicitVolumeUnlock)
            XCTAssertEqual(plan.restorability, .irreversible)

            // Second volume confirmation gate blocks execution until checked.
            state.tools.executePendingPlan()
            XCTAssertFalse(state.tools.isExecutingPlan)
            state.tools.dockerVolumeConfirmationChecked = true
            state.tools.executePendingPlan()
            try await waitUntil { !state.tools.isExecutingPlan && state.tools.lastExecutionReport != nil }

            let report = try XCTUnwrap(state.tools.lastExecutionReport)
            XCTAssertEqual(report.outcome, .partial)
            state.reloadJournalEntries()
            XCTAssertGreaterThanOrEqual(state.journalSummary.partialOrFailedCount, 1)
        }
    }

    @MainActor
    func testNewToolsMenuRoutesAndMainViewsRenderInLightAndDarkESAndEN() async throws {
        try await withSandboxState { state, sandbox, _ in
            state.completeWelcome()
            var scan = ScanResult()
            let sample = IndexedFile(
                id: "dev-cache-1",
                path: sandbox.appendingPathComponent("Library/Caches/Sample/data.cache").path,
                root: sandbox.appendingPathComponent("Library/Caches").path,
                identity: FileIdentity(device: 1, inode: 10, size: 16_384, modified: 1, changed: 1),
                allocatedBytes: 16_384,
                category: .cache,
                modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                eligible: true,
                reason: "eligible",
                confidence: "high",
                storageCategory: .appCaches,
                sourceGroup: "Sample"
            )
            scan.files = [sample]
            scan.categories = [
                CategoryReport(
                    category: .appCaches,
                    status: .measured,
                    itemCount: 1,
                    eligibleCount: 1,
                    allocatedBytes: 16_384,
                    logicalBytes: 16_384,
                    reclaimableBytes: 16_384
                )
            ]
            scan.complete = true
            scan.finishedAt = Date()
            state.scan = scan
            state.tools.expandedMenuCategories.insert(.appCaches)
            state.tools.dockerSnapshot = DockerInspectionSnapshot(
                status: .ready,
                executablePath: "/usr/local/bin/docker",
                clientVersion: "29.0.0",
                serverVersion: "29.0.0",
                builderName: "default",
                statusDetailES: "Docker disponible",
                statusDetailEN: "Docker ready",
                summaries: [],
                images: [
                    DockerImageResource(
                        id: "sha256:img-render",
                        shortID: "img-render",
                        repository: "postgres",
                        tag: "16",
                        digest: "sha256:aaa",
                        createdAt: "2026-10-01",
                        createdSince: "4 weeks ago",
                        virtualSizeBytes: 320_000_000,
                        sharedBytes: 120_000_000,
                        uniqueBytes: 200_000_000,
                        containerCount: 0,
                        referencingContainerIDs: [],
                        referencingContainerNames: [],
                        isUsedByRunningContainer: false
                    )
                ],
                containers: [],
                buildCacheRecords: [],
                volumes: [
                    DockerVolumeResource(
                        name: "pgdata",
                        driver: "local",
                        scope: "local",
                        mountpoint: "/var/lib/docker/volumes/pgdata/_data",
                        labels: "",
                        sizeBytes: 64_000_000,
                        linkCount: 0,
                        mountedByContainerIDs: [],
                        mountedByContainerNames: [],
                        isMountedByRunningContainer: false,
                        protectedByDefault: true
                    )
                ]
            )

            let scratchDir = ProcessInfo.processInfo.environment["BRISA_RENDER_SCRATCH_DIR"]

            @MainActor
            func renderView<V: View>(
                _ view: V,
                width: CGFloat,
                height: CGFloat? = nil,
                appearance: NSAppearance.Name,
                filename: String
            ) throws {
                let hosting = NSHostingView(rootView: view)
                hosting.appearance = NSAppearance(named: appearance)
                let fitting = hosting.fittingSize
                let size = NSSize(width: width, height: height ?? max(220, ceil(fitting.height)))
                hosting.frame = NSRect(origin: .zero, size: size)
                hosting.layoutSubtreeIfNeeded()
                let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                XCTAssertGreaterThan(rep.pixelsWide, 0)
                if let scratchDir {
                    let dir = URL(fileURLWithPath: scratchDir)
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                    try png.write(to: dir.appendingPathComponent(filename))
                }
            }

            // 1. MenuBar root with expanded inline category (ES Light)
            L10n.setPreference("es")
            try renderView(
                MenuPanel().environmentObject(state).environment(\.locale, Locale(identifier: "es")),
                width: 392,
                appearance: .aqua,
                filename: "menu-expanded-es-light.png"
            )

            // 2. MenuBar inline Docker route + Plan review
            state.tools.pushMenuRoute(.toolDocker)
            L10n.setPreference("en")
            try renderView(
                MenuPanel().environmentObject(state).preferredColorScheme(.dark).environment(\.locale, Locale(identifier: "en")),
                width: 392,
                appearance: .darkAqua,
                filename: "menu-docker-en-dark.png"
            )

            state.tools.prepareInventoryPlan(selectedFiles: [sample], fromMenuBar: true)
            L10n.setPreference("es")
            try renderView(
                MenuPanel().environmentObject(state).environment(\.locale, Locale(identifier: "es")),
                width: 392,
                appearance: .aqua,
                filename: "menu-plan-es-light.png"
            )

            // 3. Main Window Clean (Advanced Tools), Duplicates, Settings > Advanced & Activity
            state.openAdvancedTools(.docker)
            try renderView(
                RootView().environmentObject(state).environmentObject(state.liveMetrics)
                    .frame(width: 1080, height: 720)
                    .environment(\.locale, Locale(identifier: "es")),
                width: 1080,
                height: 720,
                appearance: .aqua,
                filename: "window-tools-docker-es-light.png"
            )

            state.openDuplicates()
            try renderView(
                RootView().environmentObject(state).environmentObject(state.liveMetrics)
                    .frame(width: 1080, height: 720)
                    .environment(\.locale, Locale(identifier: "es")),
                width: 1080,
                height: 720,
                appearance: .aqua,
                filename: "window-clean-duplicates-es-light.png"
            )

            state.openSettings(expandAdvanced: true)
            try renderView(
                RootView().environmentObject(state).environmentObject(state.liveMetrics)
                    .frame(width: 1080, height: 720)
                    .environment(\.locale, Locale(identifier: "en")),
                width: 1080,
                height: 720,
                appearance: .darkAqua,
                filename: "window-settings-advanced-en-dark.png"
            )

            L10n.setPreference("en")
            try renderView(
                ActivityView().environmentObject(state)
                    .frame(width: 820)
                    .background(Palette.background)
                    .preferredColorScheme(.dark)
                    .environment(\.locale, Locale(identifier: "en")),
                width: 820,
                appearance: .darkAqua,
                filename: "window-activity-en-dark.png"
            )
        }
    }

    func testJournalSummaryDoesNotDoubleCountTrashPlansAndLocalizesActivityLabels() {
        let planEntry = JournalEntry(
            id: "plan-abc",
            operation: "exact_duplicates.plan",
            originalPath: "/tmp/dup-copy.bin",
            size: 393_216,
            allocatedBytes: 393_216,
            status: "completed",
            domain: "exact_duplicates",
            mechanism: "trash",
            restorable: true,
            planID: "abc",
            outcomeKind: "completed",
            summaryTitle: "Move 1 duplicate copy(ies) to Trash",
            summaryTitleES: "Mover 1 copia(s) duplicada(s) a la Papelera"
        )
        let itemEntry = JournalEntry(
            id: "item-1",
            operation: "exact_duplicates.trash",
            originalPath: "/tmp/dup-copy.bin",
            size: 393_216,
            allocatedBytes: 393_216,
            trashPath: "/Users/test/.Trash/dup-copy.bin",
            status: "trashed",
            domain: "exact_duplicates",
            mechanism: "trash",
            restorable: true,
            planID: "abc",
            outcomeKind: "completed"
        )

        let summary = JournalSummary.compute(from: [planEntry, itemEntry])
        XCTAssertEqual(summary.trashedCount, 1)
        XCTAssertEqual(summary.trashedBytes, 393_216)
        XCTAssertEqual(summary.completedPlansCount, 1)

        let rejectedPlan = JournalEntry(
            id: "plan-def",
            operation: "exact_duplicates.plan",
            originalPath: "/tmp/changed-copy.bin",
            size: 100_000,
            allocatedBytes: 100_000,
            status: "rejected",
            domain: "exact_duplicates",
            mechanism: "trash",
            restorable: false,
            planID: "def",
            outcomeKind: "rejected"
        )
        let rejectedItem = JournalEntry(
            id: "item-2",
            operation: "exact_duplicates.trash",
            originalPath: "/tmp/changed-copy.bin",
            size: 100_000,
            allocatedBytes: 100_000,
            status: "rejected",
            domain: "exact_duplicates",
            mechanism: "trash",
            restorable: false,
            planID: "def",
            outcomeKind: "rejected"
        )
        let rejSummary = JournalSummary.compute(from: [rejectedPlan, rejectedItem])
        XCTAssertEqual(rejSummary.rejectedCount, 1)
        XCTAssertEqual(rejSummary.rejectedBytes, 100_000)
        XCTAssertEqual(rejSummary.partialOrFailedCount, 1)

        L10n.setPreference("es")
        XCTAssertEqual(L10n.Activity.entryMechanism("trash"), "Mecanismo: Papelera")
        XCTAssertEqual(L10n.Activity.entryDomain("exact_duplicates"), "Ámbito: Duplicados exactos")
        L10n.setPreference("en")
        XCTAssertEqual(L10n.Activity.entryMechanism("tool_command"), "Mechanism: Official command")
        XCTAssertEqual(L10n.Activity.entryDomain("docker"), "Domain: Docker")
    }

    @MainActor
    func testMenuReviewActionOpensVerifiedCandidatesWhenFirstCategoryOnlyHasProtectedItems() async throws {
        try await withSandboxState { state, sandbox, mover in
            let cachesRoot = sandbox.appendingPathComponent("Library/Caches", isDirectory: true)
            let cacheDir = cachesRoot.appendingPathComponent("com.test.sample", isDirectory: true)
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            state.preferences.roots = [cachesRoot.path]
            state.completeWelcome()
            var revealedWindow = false
            state.revealWindow = { revealedWindow = true }
            let cacheFile = cacheDir.appendingPathComponent("cache.cache")
            try Data(repeating: 0x41, count: 8192).write(to: cacheFile)
            let oldDate = Date().addingTimeInterval(-10 * 86400)
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: cacheFile.path)
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: cacheDir.path)
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: cachesRoot.path)

            var st = stat()
            XCTAssertEqual(lstat(cacheFile.path, &st), 0)
            let cacheIdentity = SafetyPolicy.identity(st)

            let firstCategory = try XCTUnwrap(StorageCategory.allCases.first)
            let lastCategory = try XCTUnwrap(StorageCategory.allCases.last { $0 != firstCategory })

            let protectedFirst = IndexedFile(
                id: "protected-first",
                path: sandbox.appendingPathComponent("Protected/disk.img").path,
                root: sandbox.path,
                identity: FileIdentity(device: 1, inode: 901, size: 500_000, modified: 1, changed: 1),
                allocatedBytes: 500_000,
                category: .other,
                modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                eligible: false,
                reason: "Protected item in first category",
                confidence: "high",
                storageCategory: firstCategory,
                logicalBytes: 500_000
            )
            let candidateLater = IndexedFile(
                id: "candidate-later",
                path: cacheFile.path,
                root: sandbox.appendingPathComponent("Library/Caches").path,
                identity: cacheIdentity,
                allocatedBytes: 8192,
                category: .cache,
                modifiedAt: oldDate,
                eligible: true,
                reason: "Verified app cache candidate",
                confidence: "high",
                storageCategory: lastCategory,
                logicalBytes: 8192
            )

            var scan = ScanResult()
            scan.files = [protectedFirst, candidateLater]
            scan.categories = scan.categories.map { report in
                var copy = report
                copy.status = .measured
                return copy
            }
            scan.finishedAt = Date()
            scan.rebuildCategoryAggregates()
            state.scan = scan
            state.categories = scan.categories

            let firstNonEmptyReport = try XCTUnwrap(state.categories.first { $0.itemCount > 0 })
            XCTAssertEqual(firstNonEmptyReport.category, firstCategory)
            XCTAssertEqual(firstNonEmptyReport.eligibleCount, 0)
            XCTAssertTrue(state.selected.isEmpty)

            MenuPanelLiveBridge.performReviewAction(state: state, tools: state.tools)

            XCTAssertFalse(revealedWindow)
            XCTAssertEqual(state.tools.menuRoute, .reviewCandidates)
            XCTAssertTrue(state.selected.isEmpty)

            state.selectAllEligible(10)
            XCTAssertEqual(state.selected, Set([candidateLater.id]))

            state.tools.prepareInventoryPlan(selectedFiles: state.selectedFiles, fromMenuBar: true)
            XCTAssertEqual(state.tools.menuRoute, .reviewPlan)
            let plan = try XCTUnwrap(state.tools.pendingPlanContext?.plan)
            XCTAssertEqual(plan.mechanism, .trash)
            XCTAssertTrue(plan.restorability.admitsRestore)

            state.tools.executePendingPlan()
            try await waitUntil { !state.tools.isExecutingPlan && state.tools.lastExecutionReport != nil }

            let report = try XCTUnwrap(state.tools.lastExecutionReport)
            XCTAssertEqual(state.tools.menuRoute, .executionResult)
            XCTAssertEqual(report.outcome, .completed, report.summaryEN)
            XCTAssertEqual(report.completedItems, [candidateLater.path])
            XCTAssertTrue(mover.movedPaths.contains(Paths.normalized(cacheFile.path)))
        }
    }

    func testPrimaryLabelsAvoidImplementationJargonInSpanishAndEnglish() {
        let previousLang = L10n.currentPreference
        defer { L10n.setPreference(previousLang) }

        let disallowedTerms = [
            "adaptadores",
            "json oficial",
            "sha-256 en streaming",
            "streaming sha-256",
            "official json"
        ]

        for lang in ["es", "en"] {
            L10n.setPreference(lang)
            let level1Strings = [
                L10n.Common.navOverview,
                L10n.Common.navFindings,
                L10n.Common.navApplications,
                L10n.Common.navActivity,
                L10n.Common.navSettings,
                L10n.Overview.tasksHeading,
                L10n.Overview.tasksCleanTitle,
                L10n.Overview.tasksExploreTitle,
                L10n.Overview.tasksDuplicatesTitle,
                L10n.Overview.tasksAppsTitle,
                L10n.Overview.tasksHistoryTitle,
                L10n.Findings.exploreInventoryNotice,
                L10n.Tools.title,
                L10n.Tools.subtitle,
                L10n.Tools.projectsSubtitle,
                L10n.Tools.packagesSubtitle,
                L10n.Tools.duplicatesSubtitle,
                L10n.Tools.dockerSubtitle
            ].joined(separator: "\n").lowercased()

            for term in disallowedTerms {
                XCTAssertFalse(
                    level1Strings.contains(term),
                    "Unexpected technical jargon '\(term)' in \(lang) level-1 UI copy"
                )
            }
        }
    }

    @MainActor
    func testUsabilityEdgeStatesZeroCandidatesPartialScanErrorAndCancelPreserveSafety() async throws {
        try await withSandboxState { state, sandbox, mover in
            var revealedWindow = false
            state.revealWindow = { revealedWindow = true }

            let cachePath = sandbox.appendingPathComponent("Library/Caches/com.example/recent.cache").path
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: cachePath).deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(repeating: 7, count: 4096).write(to: URL(fileURLWithPath: cachePath))

            // 1. Zero candidates & partial scan: locked bytes never count as cleanable and never open main window.
            let lockedItem = IndexedFile(
                id: "locked-vm",
                path: sandbox.appendingPathComponent("Library/Application Support/VM/disk.img").path,
                root: sandbox.path,
                identity: FileIdentity(device: 1, inode: 5001, size: 4096, modified: 1, changed: 1),
                allocatedBytes: 1_048_576,
                category: .other,
                modifiedAt: Date(),
                eligible: false,
                reason: "list-only",
                confidence: "protected",
                storageCategory: .vmContainers
            )
            var zeroCandidateScan = ScanResult()
            zeroCandidateScan.files = [lockedItem]
            zeroCandidateScan.categories = [
                CategoryReport(
                    category: .vmContainers,
                    status: .partial,
                    itemCount: 1,
                    eligibleCount: 0,
                    allocatedBytes: 1_048_576,
                    logicalBytes: 1_048_576,
                    reclaimableBytes: 0
                )
            ]
            zeroCandidateScan.complete = false
            zeroCandidateScan.skipped = 2
            state.scan = zeroCandidateScan
            state.categories = zeroCandidateScan.categories

            XCTAssertTrue(state.eligibleFiles.isEmpty)
            XCTAssertTrue(state.reviewableFilteredSummary.files.isEmpty)
            XCTAssertEqual(state.reviewableFilteredSummary.allocated, 0)
            XCTAssertFalse(state.reviewableFilteredSummary.hasReviewable)

            MenuPanelLiveBridge.performReviewAction(state: state, tools: state.tools)
            XCTAssertEqual(state.tools.menuRoute, .home)
            XCTAssertFalse(revealedWindow)

            // 2. Dismissing an error state in the menu context stays inline.
            state.lastError = "Permission required"
            state.lastError = nil
            XCTAssertFalse(revealedWindow)

            // 3. Reopening the panel preserves route and explicit user selection; cancelling plan leaves files untouched.
            let candidate = IndexedFile(
                id: "old-log",
                path: cachePath,
                root: sandbox.appendingPathComponent("Library/Caches").path,
                identity: FileIdentity(device: 1, inode: 5002, size: 4096, modified: 1, changed: 1),
                allocatedBytes: 4096,
                category: .cache,
                modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                eligible: true,
                reason: "old cache",
                confidence: "high",
                storageCategory: .appCaches
            )
            var populatedScan = ScanResult()
            populatedScan.files = [lockedItem, candidate]
            populatedScan.categories = [
                zeroCandidateScan.categories[0],
                CategoryReport(
                    category: .appCaches,
                    status: .measured,
                    itemCount: 1,
                    eligibleCount: 1,
                    allocatedBytes: 4096,
                    logicalBytes: 4096,
                    reclaimableBytes: 4096
                )
            ]
            populatedScan.complete = true
            state.scan = populatedScan
            state.categories = populatedScan.categories

            MenuPanelLiveBridge.performReviewAction(state: state, tools: state.tools)
            XCTAssertEqual(state.tools.menuRoute, .reviewCandidates)
            XCTAssertTrue(state.selected.isEmpty)

            state.toggle(candidate)
            XCTAssertEqual(state.selected, [candidate.id])

            state.liveMetrics.setMenuVisible(false)
            state.liveMetrics.setMenuVisible(true)
            let reopenedView = MenuPanel()
                .environmentObject(state)
                .environmentObject(state.tools)
            let hostedReopened = NSHostingView(rootView: reopenedView.frame(width: 392, height: 540))
            hostedReopened.layoutSubtreeIfNeeded()
            XCTAssertEqual(state.tools.menuRoute, .reviewCandidates)
            XCTAssertEqual(state.selected, [candidate.id])

            state.tools.prepareInventoryPlan(selectedFiles: state.selectedFiles, fromMenuBar: true)
            XCTAssertEqual(state.tools.menuRoute, .reviewPlan)
            state.tools.dismissPlanReview()
            XCTAssertEqual(state.tools.menuRoute, .reviewCandidates)
            XCTAssertTrue(mover.movedPaths.isEmpty)
            XCTAssertFalse(revealedWindow)
        }
    }
}
