import XCTest
import Darwin
@testable import BrisaCore

final class InventoryAndCatalogTests: XCTestCase {
    func testCatalogLoadsAllElevenCategoriesAndPreservesListOnlyAndNoThirdPartyBranding() throws {
        let loaded = try CatalogLoader.load()
        XCTAssertEqual(loaded.catalog.schemaVersion, 1)
        XCTAssertEqual(loaded.catalog.categories.count, 11)
        XCTAssertEqual(loaded.catalog.rules.count, 399)

        let rawJSON = try String(contentsOf: try XCTUnwrap(loaded.sourceURL), encoding: .utf8).lowercased()
        XCTAssertFalse(rawJSON.contains("levo"), "Catalog must not contain third-party brand strings")

        let categoriesInCatalog = Set(loaded.catalog.rules.compactMap(\.storageCategory))
        XCTAssertEqual(categoriesInCatalog, Set(StorageCategory.allCases))

        let listOnlyRules = loaded.catalog.rules.filter(\.listOnly)
        // 142 explicit listOnly rules in reference + 3 tier:"never" rules promoted to listOnly = 145
        XCTAssertEqual(listOnlyRules.count, 145)

        // All editor extensions, history, and leftovers must be listOnly
        for cat in [StorageCategory.editorExtensions, .agentAndEditorHistory, .appLeftovers] {
            let rules = loaded.catalog.rules.filter { $0.storageCategory == cat && $0.isPrimaryCategoryGroup }
            XCTAssertFalse(rules.isEmpty)
            XCTAssertTrue(rules.allSatisfy(\.listOnly), "All primary rules in \(cat.rawValue) must be listOnly")
        }

        // 15 of 16 VM rules must be listOnly
        let vmRules = loaded.catalog.rules.filter { $0.storageCategory == .vmContainers && $0.isPrimaryCategoryGroup }
        XCTAssertEqual(vmRules.count, 16)
        XCTAssertEqual(vmRules.filter(\.listOnly).count, 15)
    }

    func testCatalogLoadsFromSimulatedAppBundleLayout() throws {
        let f = try Fixture()
        let appContents = f.home.appendingPathComponent("Brisa.app/Contents", isDirectory: true)
        let macOSDir = appContents.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesDir = appContents.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

        let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleIdentifier</key>
          <string>local.brisa.testbundle</string>
          <key>CFBundleName</key>
          <string>Brisa</string>
        </dict>
        </plist>
        """
        try Data(infoPlist.utf8).write(to: appContents.appendingPathComponent("Info.plist"))

        let sourceCatalog = try XCTUnwrap( try CatalogLoader.load().sourceURL )
        try FileManager.default.copyItem(at: sourceCatalog, to: resourcesDir.appendingPathComponent("brisa-catalog.json"))

        let appBundle = try XCTUnwrap(Bundle(url: f.home.appendingPathComponent("Brisa.app")))
        let loadedFromBundle = try CatalogLoader.load(from: appBundle)
        XCTAssertEqual(loadedFromBundle.sourceKind, "app_bundle")
        XCTAssertEqual(loadedFromBundle.catalog.rules.count, 399)
    }

    func testKnownHiddenDirectoriesAllowedWhileSensitiveHiddenAndSecretsBlocked() throws {
        let f = try Fixture()
        let readPolicy = ReadAuthorizationPolicy(home: f.home.path)

        // Known developer/VM/extension/history hidden directories are allowed for metadata read
        for allowedRel in [
            ".npm/_cacache",
            ".cargo/registry/cache",
            ".colima/_lima/colima/disk",
            ".vscode/extensions/ms-python.python",
            ".claude/projects/demo-session",
            "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
        ] {
            let url = f.home.appendingPathComponent(allowedRel)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("meta".utf8).write(to: url)
            XCTAssertTrue(readPolicy.isMetadataAllowed(url.path), "Expected \(allowedRel) to be allowed for metadata")
        }

        // Credentials, keys, personal communications, and colima SSH configs are strictly forbidden
        for blockedRel in [
            ".ssh/id_ed25519",
            ".gnupg/secring.gpg",
            ".aws/credentials",
            "Library/Keychains/login.keychain-db",
            "Library/Mail/V10/data",
            ".colima/_lima/_config/user",
            ".claude/projects/demo/memory/MEMORY.md",
            ".npm/.env.local",
            ".npm/private.pem"
        ] {
            let url = f.home.appendingPathComponent(blockedRel)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("secret".utf8).write(to: url)
            XCTAssertFalse(readPolicy.isMetadataAllowed(url.path), "Expected \(blockedRel) to be blocked")
        }
    }

    func testBoundedRecursivePatternsProjectAnchorsAndInsideNotInsideGuards() throws {
        let f = try Fixture()
        let projectDir = f.home.appendingPathComponent("Projects", isDirectory: true)

        // 1. Valid SwiftPM project with Package.swift anchor and .build directory
        let swiftProject = projectDir.appendingPathComponent("MySwiftPkg", isDirectory: true)
        try FileManager.default.createDirectory(at: swiftProject.appendingPathComponent(".build"), withIntermediateDirectories: true)
        try Data("// swift-tools-version: 5.10".utf8).write(to: swiftProject.appendingPathComponent("Package.swift"))
        try Data(repeating: 1, count: 4096).write(to: swiftProject.appendingPathComponent(".build/debug.db"))

        // 2. Folder with .build but NO Package.swift anchor -> must NOT match swift-build
        let unanchored = projectDir.appendingPathComponent("RandomFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: unanchored.appendingPathComponent(".build"), withIntermediateDirectories: true)
        try Data(repeating: 2, count: 4096).write(to: unanchored.appendingPathComponent(".build/other.db"))

        // 3. Nested node_modules inside another node_modules -> notInside: ["node_modules"] must skip nested
        let jsProject = projectDir.appendingPathComponent("WebApp", isDirectory: true)
        let topNodeModules = jsProject.appendingPathComponent("node_modules", isDirectory: true)
        let nestedNodeModules = topNodeModules.appendingPathComponent("pkg-a/node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedNodeModules, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: jsProject.appendingPathComponent("package.json"))
        try Data("{}".utf8).write(to: topNodeModules.appendingPathComponent("pkg-a/package.json"))

        let readPolicy = ReadAuthorizationPolicy(
            home: f.home.path,
            projectRoots: [projectDir.path],
            allowSystemLocations: false
        )
        let catalog = try CatalogLoader.load().catalog
        let swiftRule = try XCTUnwrap(catalog.rules.first { $0.id == "swiftpm-build" })
        let nodeRule = try XCTUnwrap(catalog.rules.first { $0.id == "node-modules" })

        var swiftStats = PatternMatchStats()
        let swiftMatches = PatternMatcher.expand(
            rule: swiftRule,
            readPolicy: readPolicy,
            claimedPaths: [],
            neverTouchedPaths: [],
            cancellation: CancellationFlag(),
            maxRecursiveDepth: 4,
            stats: &swiftStats
        )
        XCTAssertEqual(swiftMatches.map(\.path), [swiftProject.appendingPathComponent(".build").path])

        var nodeStats = PatternMatchStats()
        let nodeMatches = PatternMatcher.expand(
            rule: nodeRule,
            readPolicy: readPolicy,
            claimedPaths: [],
            neverTouchedPaths: [],
            cancellation: CancellationFlag(),
            maxRecursiveDepth: 4,
            stats: &nodeStats
        )
        XCTAssertEqual(nodeMatches.map(\.path), [topNodeModules.path])
    }

    func testOverlapResolutionPreventsDoubleCountingAndRespectsSpecificity() throws {
        let f = try Fixture()
        // Create both specific package cache (~/Library/Caches/org.swift.swiftpm) and generic app cache (~/Library/Caches/com.example.app)
        let swiftpmCache = f.home.appendingPathComponent("Library/Caches/org.swift.swiftpm", isDirectory: true)
        let appCache = f.home.appendingPathComponent("Library/Caches/com.example.app", isDirectory: true)
        try FileManager.default.createDirectory(at: swiftpmCache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appCache, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 8192).write(to: swiftpmCache.appendingPathComponent("manifest.db"))
        try Data(repeating: 0x42, count: 4096).write(to: appCache.appendingPathComponent("cache.db"))

        let config = CategoryScanConfiguration(
            home: f.home.path,
            cleanupRoots: [],
            protectedPaths: [],
            projectRoots: [],
            includeSystemRoots: false,
            includeExtendedRules: false
        )
        let scan = CategoryDetector.scan(configuration: config)

        let pkgItems = scan.files.filter { $0.storageCategory == .packageCaches }
        let appItems = scan.files.filter { $0.storageCategory == .appCaches }

        XCTAssertTrue(pkgItems.contains { $0.path == swiftpmCache.path && $0.ruleID == "swiftpm-cache" })
        XCTAssertFalse(appItems.contains { $0.path == swiftpmCache.path }, "Specific swiftpm-cache must not be claimed by generic user-caches")
        XCTAssertTrue(appItems.contains { $0.path == appCache.path && $0.ruleID == "user-caches" })
    }

    func testSparseVMDiskDistinguishesVirtualLogicalAllocatedAndZeroReclaimable() throws {
        let f = try Fixture()
        let vmDir = f.home.appendingPathComponent("Library/Containers/com.docker.docker/Data/vms/0/data", isDirectory: true)
        try FileManager.default.createDirectory(at: vmDir, withIntermediateDirectories: true)
        let rawDisk = vmDir.appendingPathComponent("Docker.raw")

        // Create a sparse file with 64 MB virtual size and only 4 KB written at the beginning
        let fd = Darwin.open(rawDisk.path, O_CREAT | O_RDWR, 0o600)
        XCTAssertGreaterThanOrEqual(fd, 0)
        let written = [UInt8](repeating: 0x5A, count: 4096)
        _ = written.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        XCTAssertEqual(ftruncate(fd, 64 * 1024 * 1024), 0)
        close(fd)

        let config = CategoryScanConfiguration(
            home: f.home.path,
            cleanupRoots: [],
            protectedPaths: [],
            projectRoots: [],
            includeSystemRoots: false,
            includeExtendedRules: false
        )
        let scan = CategoryDetector.scan(configuration: config)
        let vmItem = try XCTUnwrap(scan.files.first { $0.storageCategory == .vmContainers && $0.ruleID == "docker-desktop-data" })

        XCTAssertEqual(vmItem.logicalBytes, 64 * 1024 * 1024)
        XCTAssertEqual(vmItem.virtualCapacityBytes, 64 * 1024 * 1024)
        XCTAssertLessThan(vmItem.allocatedBytes, vmItem.logicalBytes, "Allocated APFS blocks must be smaller than sparse virtual capacity")
        XCTAssertEqual(vmItem.reclaimableBytes, 0, "listOnly VM must have 0 reclaimable bytes")
        XCTAssertFalse(vmItem.eligible)
        XCTAssertFalse(vmItem.selectionAllowed)
        XCTAssertTrue(vmItem.inventoryOnly)
        XCTAssertEqual(vmItem.cleanupEligibility, .inventoryOnly)
    }

    func testSymlinksAreRejectedInPatternExpansionAndDirectoryMeasurement() throws {
        let f = try Fixture()
        let outsideTarget = f.home.appendingPathComponent("OutsideSecret", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideTarget, withIntermediateDirectories: true)
        let secretFile = outsideTarget.appendingPathComponent("data.bin")
        try Data(repeating: 0x7F, count: 32_768).write(to: secretFile)

        // Place a symlink inside ~/.npm/_cacache pointing outside
        let npmCache = f.home.appendingPathComponent(".npm/_cacache", isDirectory: true)
        try FileManager.default.createDirectory(at: npmCache, withIntermediateDirectories: true)
        try Data(repeating: 0x11, count: 1024).write(to: npmCache.appendingPathComponent("real.bin"))
        try FileManager.default.createSymbolicLink(
            at: npmCache.appendingPathComponent("symlink_escape"),
            withDestinationURL: secretFile
        )

        // Also place a top-level symlink in ~/Library/Caches/evil-link
        let cachesDir = f.home.appendingPathComponent("Library/Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: cachesDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: cachesDir.appendingPathComponent("evil-link"),
            withDestinationURL: outsideTarget
        )

        let config = CategoryScanConfiguration(
            home: f.home.path,
            cleanupRoots: [],
            protectedPaths: [],
            projectRoots: [],
            includeSystemRoots: false
        )
        let scan = CategoryDetector.scan(configuration: config)
        XCTAssertFalse(scan.files.contains { $0.path.contains("evil-link") })

        let npmItem = try XCTUnwrap(scan.files.first { $0.ruleID == "npm-cache" })
        XCTAssertEqual(npmItem.logicalBytes, 1024, "Symlink target bytes must not be included in directory measurement")
        XCTAssertEqual(npmItem.childCount, 1)
    }

    func testListOnlyNeverTickedTypedAdapterAndUnimplementedConditionsLockCleanup() throws {
        let f = try Fixture()
        // 1. VS Code extension (listOnly: true, tier: never -> never_select)
        let vscodeExt = f.home.appendingPathComponent(".vscode/extensions/ms-vscode.cpptools", isDirectory: true)
        try FileManager.default.createDirectory(at: vscodeExt, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 2048).write(to: vscodeExt.appendingPathComponent("extension.js"))

        // 2. CocoaPods cache (has cleanCommand -> requiresTypedAdapter: true)
        let podCache = f.home.appendingPathComponent("Library/Caches/CocoaPods", isDirectory: true)
        try FileManager.default.createDirectory(at: podCache, withIntermediateDirectories: true)
        try Data(repeating: 2, count: 2048).write(to: podCache.appendingPathComponent("Pods.db"))

        // 3. Xcode DeviceSupport (has keepNewest: 2 -> hasUnverifiedCondition: true)
        let iosDeviceSupport = f.home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport/17.4 (21E213)", isDirectory: true)
        try FileManager.default.createDirectory(at: iosDeviceSupport, withIntermediateDirectories: true)
        try Data(repeating: 3, count: 2048).write(to: iosDeviceSupport.appendingPathComponent("Symbols"))

        // 4. Ruby installed gems (neverTicked: true -> lockedNeverSelect)
        let gemDir = f.home.appendingPathComponent(".gem", isDirectory: true)
        try FileManager.default.createDirectory(at: gemDir, withIntermediateDirectories: true)
        try Data(repeating: 4, count: 2048).write(to: gemDir.appendingPathComponent("bundler.gem"))

        // 5. Eligible old regular .cache file inside authorized cleanup root
        let cachesRoot = f.home.appendingPathComponent("Library/Caches", isDirectory: true)
        let eligibleFile = try f.file("standalone.cache", days: 30, size: 4096, directory: cachesRoot)

        var config = CategoryScanConfiguration(
            home: f.home.path,
            cleanupRoots: [cachesRoot.path],
            protectedPaths: [],
            projectRoots: [],
            includeSystemRoots: false
        )
        // This fixture controls its process environment; live host agents are tested separately.
        config.environmentSnapshot = SystemEnvironmentSnapshot()
        let scan = CategoryDetector.scan(configuration: config)

        let extItem = try XCTUnwrap(scan.files.first { $0.ruleID == "vscode-old-extensions" })
        XCTAssertFalse(extItem.eligible)
        XCTAssertFalse(extItem.selectionAllowed)
        XCTAssertTrue(extItem.inventoryOnly)
        XCTAssertEqual(extItem.cleanupEligibility, .inventoryOnly)

        let gemItem = try XCTUnwrap(scan.files.first { $0.ruleID == "ruby-installed-gems" })
        XCTAssertFalse(gemItem.eligible)
        XCTAssertFalse(gemItem.selectionAllowed)
        XCTAssertEqual(gemItem.cleanupEligibility, .lockedNeverSelect)

        let podItem = try XCTUnwrap(scan.files.first { $0.ruleID == "cocoapods-cache" })
        XCTAssertFalse(podItem.eligible)
        XCTAssertFalse(podItem.selectionAllowed)
        XCTAssertEqual(podItem.cleanupEligibility, .lockedRequiresTypedAdapter)
        XCTAssertEqual(podItem.reason, "requires_typed_adapter")

        let sdkItem = try XCTUnwrap(scan.files.first { $0.ruleID == "xcode-ios-device-support" })
        XCTAssertFalse(sdkItem.eligible)
        XCTAssertFalse(sdkItem.selectionAllowed)
        XCTAssertEqual(sdkItem.cleanupEligibility, .lockedUnverifiedCondition)
        XCTAssertEqual(sdkItem.reason, "unverified_condition")

        let standItem = try XCTUnwrap(scan.files.first { $0.path == eligibleFile.path })
        XCTAssertTrue(standItem.eligible)
        XCTAssertTrue(standItem.selectionAllowed)
        XCTAssertFalse(standItem.inventoryOnly)
        XCTAssertEqual(standItem.cleanupEligibility, .eligible)
    }

    func testCategoryStatusesDistinguishNotInstalledEmptyMeasuredAndCancelled() throws {
        let f = try Fixture()
        // Create empty Downloads directory so downloads_installers has an existing base root but 0 matching installer files -> .empty
        try FileManager.default.createDirectory(at: f.home.appendingPathComponent("Downloads"), withIntermediateDirectories: true)
        // Create a measured file in ~/.npm/_cacache -> package_caches is .measured
        let npm = f.home.appendingPathComponent(".npm/_cacache", isDirectory: true)
        try FileManager.default.createDirectory(at: npm, withIntermediateDirectories: true)
        try Data(repeating: 0x33, count: 1024).write(to: npm.appendingPathComponent("blob"))

        let config = CategoryScanConfiguration(
            home: f.home.path,
            cleanupRoots: [],
            protectedPaths: [],
            projectRoots: [],
            includeSystemRoots: false
        )
        let scan = CategoryDetector.scan(configuration: config)

        let pkgReport = try XCTUnwrap(scan.categories.first { $0.category == .packageCaches })
        XCTAssertEqual(pkgReport.status, .measured)
        XCTAssertEqual(pkgReport.itemCount, 1)

        let dlReport = try XCTUnwrap(scan.categories.first { $0.category == .downloadsAndInstallers })
        XCTAssertEqual(dlReport.status, .empty, "Existing Downloads folder with no matching .dmg/.pkg/.ipsw must report .empty")

        let vmReport = try XCTUnwrap(scan.categories.first { $0.category == .vmContainers })
        XCTAssertEqual(vmReport.status, .notInstalled, "Absent VM directories must report .notInstalled, not 0 B measured")

        // Verify pre-cancelled scan marks categories as partial and scan.cancelled = true
        let cancelledFlag = CancellationFlag()
        cancelledFlag.cancel()
        let cancelledScan = CategoryDetector.scan(configuration: config, cancellation: cancelledFlag)
        XCTAssertTrue(cancelledScan.cancelled)
        XCTAssertFalse(cancelledScan.complete)
        XCTAssertTrue(cancelledScan.categories.allSatisfy { $0.status == .partial })
    }

    func testRegenerationBehaviorPropagatesAndAllCatalogRulesResolveGuidance() throws {
        let loaded = try CatalogLoader.load()
        XCTAssertGreaterThanOrEqual(loaded.catalog.rules.count, 399)

        for rule in loaded.catalog.rules {
            let details = RegenerationGuidance.describe(
                sourceGroup: rule.sourceGroup,
                regenBehavior: rule.regenBehavior,
                category: rule.storageCategory,
                tier: rule.tier
            )
            XCTAssertFalse(details.familyTitleES.isEmpty, "Missing Spanish family title for \(rule.id)")
            XCTAssertFalse(details.familyTitleEN.isEmpty, "Missing English family title for \(rule.id)")
            XCTAssertFalse(details.whatItIsES.isEmpty, "Missing Spanish description for \(rule.id)")
            XCTAssertFalse(details.whatItIsEN.isEmpty, "Missing English description for \(rule.id)")
            XCTAssertFalse(details.whatIsLostES.isEmpty, "Missing Spanish loss note for \(rule.id)")
            XCTAssertFalse(details.whatIsLostEN.isEmpty, "Missing English loss note for \(rule.id)")
            XCTAssertFalse(details.regenerationES.isEmpty, "Missing Spanish regen note for \(rule.id)")
            XCTAssertFalse(details.regenerationEN.isEmpty, "Missing English regen note for \(rule.id)")
            XCTAssertNotEqual(details.behavior, .unknown, "Expected concrete behavior for \(rule.id)")
        }

        XCTAssertEqual(RegenerationBehavior(rawBehavior: "rebuilt"), .rebuilds)

        // Verify scan propagation on measured files in a controlled home.
        let f = try Fixture()
        let derived = f.home.appendingPathComponent("Library/Developer/Xcode/DerivedData/DemoApp")
        try FileManager.default.createDirectory(at: derived, withIntermediateDirectories: true)
        try Data(repeating: 0x11, count: 2048).write(to: derived.appendingPathComponent("build.db"))

        let downloads = f.home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try Data(repeating: 0x22, count: 4096).write(to: downloads.appendingPathComponent("Setup.dmg"))

        let config = CategoryScanConfiguration(
            home: f.home.path,
            cleanupRoots: [],
            protectedPaths: [],
            projectRoots: [],
            includeSystemRoots: false
        )
        let scan = CategoryDetector.scan(configuration: config)
        let derivedItem = try XCTUnwrap(scan.files.first { $0.path.hasSuffix("DerivedData/DemoApp") || $0.path.contains("/DerivedData") })
        XCTAssertNotNil(derivedItem.regenBehavior)
        let derivedGuidance = RegenerationGuidance.describe(for: derivedItem)
        XCTAssertEqual(derivedGuidance.behavior, .rebuilds)

        let dmgItem = try XCTUnwrap(scan.files.first { $0.path.hasSuffix("Setup.dmg") })
        XCTAssertEqual(dmgItem.regenBehavior, "gone")
        XCTAssertEqual(RegenerationGuidance.describe(for: dmgItem).behavior, .gone)
    }
}
