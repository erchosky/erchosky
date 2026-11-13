import XCTest
@testable import BrisaCore

final class AppUninstallerTests: XCTestCase {
    private final class MutableRunningChecker: AppRunningChecking, @unchecked Sendable {
        private let lock = NSLock()
        private var current: [RunningAppProcessInfo]
        init(_ initial: [RunningAppProcessInfo]) { self.current = initial }
        func set(_ next: [RunningAppProcessInfo]) { lock.withLock { current = next } }
        func runningProcesses(for app: InstalledAppDescriptor) -> [RunningAppProcessInfo] {
            lock.withLock { current }
        }
    }

    private func makeMockApp(at url: URL, name: String, bundleID: String, groups: [String] = []) throws {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try Data("#!/bin/sh\necho ok\n".utf8).write(to: macOS.appendingPathComponent(name))
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": name,
            "CFBundleShortVersionString": "2.1.0",
            "BrisaAppGroups": groups
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    func testAssociationTiersProtectSharedGroupUserDocsAndPrivilegedComponents() throws {
        let f = try Fixture()
        let appsDir = f.home.appendingPathComponent("Applications", isDirectory: true)
        let sysLibrary = f.home.appendingPathComponent("FakeSystemLibrary", isDirectory: true)
        let trashDir = f.home.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: appsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)

        let targetApp = appsDir.appendingPathComponent("StudioPro.app", isDirectory: true)
        let siblingApp = appsDir.appendingPathComponent("StudioHelper.app", isDirectory: true)
        try makeMockApp(at: targetApp, name: "StudioPro", bundleID: "com.studio.StudioPro", groups: ["GRP123.com.studio.suite"])
        try makeMockApp(at: siblingApp, name: "StudioHelper", bundleID: "com.studio.StudioHelper", groups: ["GRP123.com.studio.suite"])

        // 1. Exclusive bundle-ID artifacts
        let appSupportID = f.home.appendingPathComponent("Library/Application Support/com.studio.StudioPro", isDirectory: true)
        let cachesID = f.home.appendingPathComponent("Library/Caches/com.studio.StudioPro", isDirectory: true)
        let prefsDir = f.home.appendingPathComponent("Library/Preferences", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupportID, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cachesID, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: prefsDir, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4096).write(to: appSupportID.appendingPathComponent("state.db"))
        try Data(repeating: 2, count: 8192).write(to: cachesID.appendingPathComponent("thumb.cache"))
        try Data("plist".utf8).write(to: prefsDir.appendingPathComponent("com.studio.StudioPro.plist"))

        // 2. Shared Group Container + shared vendor dir
        let sharedGroup = f.home.appendingPathComponent("Library/Group Containers/GRP123.com.studio.suite", isDirectory: true)
        let vendorShared = f.home.appendingPathComponent("Library/Application Support/studio", isDirectory: true)
        try FileManager.default.createDirectory(at: sharedGroup, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vendorShared, withIntermediateDirectories: true)
        try Data("shared".utf8).write(to: sharedGroup.appendingPathComponent("license.dat"))
        try Data("vendor".utf8).write(to: vendorShared.appendingPathComponent("presets.dat"))

        // 3. Uncertain name-only match (NO bundle ID)
        let fuzzySupport = f.home.appendingPathComponent("Library/Application Support/StudioPro", isDirectory: true)
        try FileManager.default.createDirectory(at: fuzzySupport, withIntermediateDirectories: true)
        try Data("fuzzy".utf8).write(to: fuzzySupport.appendingPathComponent("notes.txt"))

        // 4. User documents -> MUST NEVER be touched or listed
        let userDocs = f.home.appendingPathComponent("Documents/StudioPro", isDirectory: true)
        try FileManager.default.createDirectory(at: userDocs, withIntermediateDirectories: true)
        try Data("my-work".utf8).write(to: userDocs.appendingPathComponent("project.doc"))

        // 5. System-wide /Library helper daemon -> flagged pending privileges, never auto-selected
        let sysDaemons = sysLibrary.appendingPathComponent("LaunchDaemons", isDirectory: true)
        try FileManager.default.createDirectory(at: sysDaemons, withIntermediateDirectories: true)
        let daemonPlist = sysDaemons.appendingPathComponent("com.studio.StudioPro.helper.plist")
        try Data("daemon".utf8).write(to: daemonPlist)

        let running = MutableRunningChecker([RunningAppProcessInfo(pid: 991, processName: "StudioPro", bundleIdentifier: "com.studio.StudioPro")])
        let journal = Journal(store: try f.store())
        let uninstaller = AppUninstaller(
            journal: journal,
            home: f.home.path,
            systemRoots: [sysLibrary.path],
            runningChecker: running,
            mover: ControlledTrash(directory: trashDir),
            selfBundleIdentifier: "local.brisa.app",
            selfBundlePath: "/Applications/Brisa.app"
        )

        let inspection = uninstaller.inspect(appBundlePath: targetApp.path, otherInstalledAppPaths: [siblingApp.path])
        XCTAssertTrue(inspection.isRunning)
        XCTAssertFalse(inspection.relatedItems.contains { $0.path.contains("/Documents/") })

        XCTAssertEqual(inspection.exclusiveItems.filter { !$0.requiresPrivileges }.count, 3)
        XCTAssertTrue(inspection.exclusiveItems.filter { !$0.requiresPrivileges }.allSatisfy { $0.defaultSelected && $0.confidence == .highBundleID })

        let daemonItem = try XCTUnwrap(inspection.privilegedPendingItems.first)
        XCTAssertEqual(daemonItem.path, Paths.normalized(daemonPlist.path))
        XCTAssertFalse(daemonItem.defaultSelected)

        XCTAssertTrue(inspection.possibleSharedItems.contains { $0.path == Paths.normalized(sharedGroup.path) && $0.sharedWithApps == ["StudioHelper"] })
        XCTAssertTrue(inspection.possibleSharedItems.allSatisfy { !$0.defaultSelected })

        XCTAssertEqual(inspection.uncertainItems.count, 1)
        XCTAssertEqual(inspection.uncertainItems.first?.confidence, .lowNameOnly)
        XCTAssertFalse(inspection.uncertainItems.first?.defaultSelected ?? true)

        // While app is running, plan must block with canRecheck == true
        let defaultIDs = Set(inspection.relatedItems.filter(\.defaultSelected).map(\.id))
        let blockedPlan = uninstaller.buildPlan(inspection: inspection, selectedItemIDs: defaultIDs)
        XCTAssertFalse(blockedPlan.canExecute)
        XCTAssertTrue(blockedPlan.blockers.contains(where: \.canRecheck))

        // Attempting to explicitly select shared item must still block that shared item
        let withShared = uninstaller.buildPlan(inspection: inspection, selectedItemIDs: [Paths.normalized(sharedGroup.path)])
        XCTAssertTrue(withShared.blockedResources.contains { $0.pathOrIdentifier == Paths.normalized(sharedGroup.path) })

        // User quits app -> recheck -> execute succeeds!
        running.set([])
        let rechecked = uninstaller.inspect(appBundlePath: targetApp.path, otherInstalledAppPaths: [siblingApp.path])
        XCTAssertFalse(rechecked.isRunning)
        let execPlan = uninstaller.buildPlan(inspection: rechecked, selectedItemIDs: defaultIDs)
        XCTAssertTrue(execPlan.canExecute)

        let report = try uninstaller.execute(plan: execPlan, inspection: rechecked)
        XCTAssertEqual(report.outcome, .completed)
        XCTAssertTrue(report.restorable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetApp.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: appSupportID.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sharedGroup.path), "Shared data must be kept")
        XCTAssertTrue(FileManager.default.fileExists(atPath: userDocs.path), "User documents must be kept")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fuzzySupport.path), "Uncertain match untouched")
        XCTAssertTrue(FileManager.default.fileExists(atPath: daemonPlist.path), "Privileged item left pending")
    }

    func testRelaunchBeforeExecuteAndSystemAppProtectionAreRejected() throws {
        let f = try Fixture()
        let appsDir = f.home.appendingPathComponent("Applications", isDirectory: true)
        let trashDir = f.home.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: appsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)

        let appURL = appsDir.appendingPathComponent("Editor.app", isDirectory: true)
        try makeMockApp(at: appURL, name: "Editor", bundleID: "com.example.Editor")

        let running = MutableRunningChecker([])
        let uninstaller = AppUninstaller(
            journal: Journal(store: try f.store()),
            home: f.home.path,
            runningChecker: running,
            mover: ControlledTrash(directory: trashDir)
        )
        let inspection = uninstaller.inspect(appBundlePath: appURL.path)
        let plan = uninstaller.buildPlan(inspection: inspection, selectedItemIDs: [])
        XCTAssertTrue(plan.canExecute)

        // App reopens right before execution -> live check must reject without trashing!
        running.set([RunningAppProcessInfo(pid: 888, processName: "Editor", bundleIdentifier: "com.example.Editor")])
        let report = try uninstaller.execute(plan: plan, inspection: inspection)
        XCTAssertEqual(report.outcome, .rejected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: appURL.path))

        // System-protected Apple bundle under `/Applications` or Brisa itself
        let brisaSelf = appsDir.appendingPathComponent("Brisa.app", isDirectory: true)
        try makeMockApp(at: brisaSelf, name: "Brisa", bundleID: "local.brisa.app")
        let selfUninstaller = AppUninstaller(
            journal: Journal(store: try f.store()),
            home: f.home.path,
            mover: ControlledTrash(directory: trashDir),
            selfBundleIdentifier: "local.brisa.app",
            selfBundlePath: brisaSelf.path
        )
        let selfInsp = selfUninstaller.inspect(appBundlePath: brisaSelf.path)
        XCTAssertTrue(selfInsp.app.isSystemProtected)
        let selfPlan = selfUninstaller.buildPlan(inspection: selfInsp, selectedItemIDs: [])
        XCTAssertFalse(selfPlan.canExecute)
    }
}
