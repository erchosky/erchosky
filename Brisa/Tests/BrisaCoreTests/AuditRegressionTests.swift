import XCTest
import Darwin
@testable import BrisaCore

final class AuditRegressionTests: XCTestCase {
    private static func catalog(rules: [CatalogRule]) throws -> URL {
        let categories = StorageCategory.allCases.map {
            CatalogCategoryDescriptor(
                id: $0.rawValue,
                titleES: $0.titleES,
                titleEN: $0.titleEN,
                icon: $0.icon,
                whatItIsES: $0.aboutES,
                whatItIsEN: $0.aboutEN,
                whySafeES: "Solo para pruebas.",
                whySafeEN: "Test only.",
                howItComesBackES: "Se recrea en pruebas.",
                howItComesBackEN: "Recreated in tests."
            )
        }
        let catalog = StorageCatalog(schemaVersion: 1, catalogName: "audit-fixture", categories: categories, rules: rules)
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("brisa-audit-\(UUID().uuidString).json")
        try JSONEncoder().encode(catalog).write(to: url)
        return url
    }

    private static func rule(
        id: String,
        category: StorageCategory?,
        patterns: [String],
        tier: DataTier = .costly,
        listOnly: Bool = true,
        neverTicked: Bool = false
    ) -> CatalogRule {
        CatalogRule(
            id: id,
            sourceGroup: "audit",
            isPrimaryCategoryGroup: true,
            displayCategory: category?.rawValue ?? "never_touched",
            titleES: id,
            titleEN: id,
            explanationES: "Fixture rule",
            explanationEN: "Fixture rule",
            patterns: patterns,
            tier: tier,
            listOnly: listOnly,
            neverTicked: neverTicked
        )
    }

    func testPartialDirectoryMustNotBeReportedAsComplete() throws {
        let f = try Fixture()
        let caches = f.home.appendingPathComponent("Library/Caches/HugeCache", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        for idx in 0..<2_105 {
            try Data("x".utf8).write(to: caches.appendingPathComponent("f-\(idx).dat"))
        }
        let catalog = try Self.catalog(rules: [
            Self.rule(id: "audit-huge-cache", category: .appCaches, patterns: ["~/Library/Caches/HugeCache"])
        ])
        let scan = CategoryDetector.scan(configuration: InventoryScanConfiguration(
            home: f.home.path, allowSystemLocations: false, includeExtendedRules: false, catalogURL: catalog
        ))
        let report = try XCTUnwrap(scan.categories.first { $0.category == .appCaches })
        print("AUDIT partial: files=\(scan.files.first?.childCount ?? 0)/2105 status=\(report.status.rawValue) complete=\(scan.complete)")
        XCTAssertEqual(report.status, .partial, "A 2000-entry measurement is not a complete 2105-file directory")
        XCTAssertFalse(scan.complete)
    }

    func testCategoryMustNotSilentlyDropCandidatesAfter120() throws {
        let f = try Fixture()
        let caches = f.home.appendingPathComponent("Library/Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        for idx in 0..<150 {
            try Data("x".utf8).write(to: caches.appendingPathComponent("file-\(idx).cache"))
        }
        let catalog = try Self.catalog(rules: [
            Self.rule(id: "audit-caches", category: .appCaches, patterns: ["~/Library/Caches/*.cache"])
        ])
        let scan = CategoryDetector.scan(configuration: InventoryScanConfiguration(
            home: f.home.path, allowSystemLocations: false, includeExtendedRules: false, catalogURL: catalog
        ))
        let report = try XCTUnwrap(scan.categories.first { $0.category == .appCaches })
        print("AUDIT cap: indexed=\(scan.files.count)/150 status=\(report.status.rawValue) complete=\(scan.complete)")
        XCTAssertEqual(scan.files.count, 150, "The scan budget is ample for all 150 files; pagination must not discard inventory")
    }

    func testSpecificRuleMustNotHideUnclaimedSiblingBytes() throws {
        let f = try Fixture()
        let mixed = f.home.appendingPathComponent("Library/Caches/Mixed", isDirectory: true)
        let specific = mixed.appendingPathComponent("specific", isDirectory: true)
        try FileManager.default.createDirectory(at: specific, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4_096).write(to: specific.appendingPathComponent("claimed.bin"))
        try Data(repeating: 2, count: 8_192).write(to: mixed.appendingPathComponent("unclaimed.bin"))

        let catalog = try Self.catalog(rules: [
            Self.rule(id: "audit-specific", category: .appCaches, patterns: ["~/Library/Caches/Mixed/specific"]),
            Self.rule(id: "user-caches", category: .appCaches, patterns: ["~/Library/Caches/*"])
        ])
        let scan = CategoryDetector.scan(configuration: InventoryScanConfiguration(
            home: f.home.path, allowSystemLocations: false, includeExtendedRules: false, catalogURL: catalog
        ))
        print("AUDIT overlap: logical=\(scan.logicalBytes)/12288 items=\(scan.files.map { $0.ruleID })")
        XCTAssertEqual(scan.logicalBytes, 12_288, "Deduplication must keep the unclaimed sibling's 8192 bytes")
    }

    func testOpenFileMustNotBeLabeledIdleAndEligible() throws {
        let f = try Fixture()
        let caches = f.home.appendingPathComponent("Library/Caches", isDirectory: true)
        let file = try f.file("open.cache", days: 30, size: 1_024, directory: caches)
        let fd = Darwin.open(file.path, O_RDONLY)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }

        let catalog = try Self.catalog(rules: [
            Self.rule(id: "user-caches", category: .appCaches, patterns: ["~/Library/Caches/*"], tier: .regenerable, listOnly: false)
        ])
        let scan = CategoryDetector.scan(configuration: InventoryScanConfiguration(
            home: f.home.path, roots: [caches.path], allowSystemLocations: false,
            includeExtendedRules: false, catalogURL: catalog
        ))
        let item = try XCTUnwrap(scan.files.first { $0.path == file.path })
        print("AUDIT open: eligible=\(item.eligible) usage=\(item.usageState.status) reclaimable=\(item.reclaimableBytes)")
        XCTAssertFalse(item.eligible, "lsof proves the fixture is currently open")
        XCTAssertNotEqual(item.usageState.status, "idle")
    }

    func testNeverTouchedCatalogRuleMustAlsoApplyToFastPath() throws {
        let f = try Fixture()
        let caches = f.home.appendingPathComponent("Library/Caches", isDirectory: true)
        let file = try f.file("never.cache", days: 30, size: 1_024, directory: caches)

        let catalog = try Self.catalog(rules: [
            Self.rule(id: "never-touch-this", category: nil, patterns: ["~/Library/Caches/never.cache"], tier: .never, listOnly: true, neverTicked: true),
            Self.rule(id: "audit-caches", category: .appCaches, patterns: ["~/Library/Caches/*.cache"], tier: .regenerable, listOnly: false)
        ])
        let scan = CategoryDetector.scan(configuration: InventoryScanConfiguration(
            home: f.home.path, roots: [caches.path], allowSystemLocations: false,
            includeExtendedRules: false, catalogURL: catalog
        ))
        let matched = scan.files.filter { $0.path == file.path }
        print("AUDIT never: \(matched.map { ($0.ruleID ?? "", $0.eligible) })")
        XCTAssertFalse(matched.contains(where: \.eligible), "The fast root pass must not override never_touched/neverTicked")
    }

    func testQCOW2VirtualCapacityMustNotBeInferredFromFileLength() throws {
        let f = try Fixture()
        let utm = f.home.appendingPathComponent("Library/Containers/com.utmapp.UTM/Data/Documents/Test.utm/Data", isDirectory: true)
        try FileManager.default.createDirectory(at: utm, withIntermediateDirectories: true)
        var header = Data(repeating: 0, count: 4_096)
        header.replaceSubrange(0..<4, with: [0x51, 0x46, 0x49, 0xfb]) // "QFI\xfb"
        header.replaceSubrange(4..<8, with: [0x00, 0x00, 0x00, 0x03]) // QCOW2 v3
        let sixtyFourGiB: UInt64 = 64 * 1_024 * 1_024 * 1_024
        var bigEndianSize = sixtyFourGiB.bigEndian
        withUnsafeBytes(of: &bigEndianSize) { header.replaceSubrange(24..<32, with: $0) }
        try header.write(to: utm.appendingPathComponent("disk.qcow2"))

        let catalog = try Self.catalog(rules: [
            Self.rule(id: "utm-vms", category: .vmContainers, patterns: ["~/Library/Containers/com.utmapp.UTM/Data/Documents/*.utm"])
        ])
        let scan = CategoryDetector.scan(configuration: InventoryScanConfiguration(
            home: f.home.path, allowSystemLocations: false, includeExtendedRules: false, catalogURL: catalog
        ))
        let item = try XCTUnwrap(scan.files.first { $0.ruleID == "utm-vms" })
        print("AUDIT qcow2: logical=\(item.logicalBytes) claimedVirtual=\(String(describing: item.virtualCapacityBytes)) headerVirtual=\(sixtyFourGiB)")
        XCTAssertNotEqual(item.virtualCapacityBytes, 4_096)
        XCTAssertTrue(item.virtualCapacityBytes == nil || item.virtualCapacityBytes == Int64(sixtyFourGiB),
                      "If no format-aware adapter is implemented, virtual capacity must be unknown, not st_size")
    }

    func testNormalConfiguredGlobalEntryBudgetMustBeRespected() throws {
        let f = try Fixture()
        let caches = f.home.appendingPathComponent("Library/Caches/Budget", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        for idx in 0..<1_500 {
            try Data("x".utf8).write(to: caches.appendingPathComponent("f-\(idx).dat"))
        }
        let catalog = try Self.catalog(rules: [
            Self.rule(id: "audit-budget", category: .appCaches, patterns: ["~/Library/Caches/Budget"])
        ])
        let scan = CategoryDetector.scan(configuration: InventoryScanConfiguration(
            home: f.home.path, allowSystemLocations: false, includeExtendedRules: false,
            maxEntries: 1_001, timeLimit: 30, catalogURL: catalog
        ))
        print("AUDIT budget: examined=\(scan.examined) configured=1001 complete=\(scan.complete)")
        XCTAssertLessThanOrEqual(scan.examined, 1_001, "The normal path must enforce the configured global entry budget too")
        XCTAssertFalse(scan.complete)
    }

    // Additional R8–R11 audit tests
    func testScanResultRebuildsCategoryAggregatesAfterMutations() throws {
        let f = try Fixture()
        let caches = f.home.appendingPathComponent("Library/Caches", isDirectory: true)
        let fileA = try f.file("a.cache", days: 30, size: 4_096, directory: caches)
        let fileB = try f.file("b.cache", days: 30, size: 8_192, directory: caches)
        let catalog = try Self.catalog(rules: [
            Self.rule(id: "user-caches", category: .appCaches, patterns: ["~/Library/Caches/*.cache"], tier: .regenerable, listOnly: false)
        ])
        var scan = CategoryDetector.scan(configuration: InventoryScanConfiguration(
            home: f.home.path, roots: [caches.path], allowSystemLocations: false,
            includeExtendedRules: false, catalogURL: catalog
        ))
        let beforeReport = try XCTUnwrap(scan.categories.first { $0.category == .appCaches })
        XCTAssertEqual(beforeReport.itemCount, 2)
        XCTAssertEqual(beforeReport.logicalBytes, 12_288)

        scan.files.removeAll { $0.path == fileA.path }
        scan.rebuildCategoryAggregates()

        let afterReport = try XCTUnwrap(scan.categories.first { $0.category == .appCaches })
        XCTAssertEqual(afterReport.itemCount, 1)
        XCTAssertEqual(afterReport.logicalBytes, 8_192)
        XCTAssertEqual(scan.files.first?.path, fileB.path)
    }

    func testInventoryRootAllowsDownloadsWhileSafetyPolicyRejectsCleanup() throws {
        let f = try Fixture()
        let downloads = f.home.appendingPathComponent("Downloads", isDirectory: true)
        let documents = f.home.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)

        // ReadAuthorizationPolicy allows authorizing ~/Downloads for read-only inventory
        let validatedDownloads = try ReadAuthorizationPolicy.validateInventoryRoot(downloads.path, home: f.home.path)
        XCTAssertEqual(validatedDownloads, downloads.path)

        // SafetyPolicy strictly rejects both ~/Downloads and ~/Documents as destructive cleanup roots
        XCTAssertThrowsError(try SafetyPolicy(roots: [downloads.path], home: f.home.path))
        XCTAssertThrowsError(try SafetyPolicy(roots: [documents.path], home: f.home.path))
    }

    func testZeroAllocatedSparseFileDoesNotSubstituteLogicalBytes() throws {
        let f = try Fixture()
        let caches = f.home.appendingPathComponent("Library/Caches/SparseDir", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        let sparseFile = caches.appendingPathComponent("hole.bin")
        let fd = Darwin.open(sparseFile.path, O_CREAT | O_RDWR, 0o600)
        XCTAssertGreaterThanOrEqual(fd, 0)
        XCTAssertEqual(ftruncate(fd, 1_048_576), 0) // 1 MiB logical hole, 0 allocated blocks
        close(fd)

        let catalog = try Self.catalog(rules: [
            Self.rule(id: "sparse-cache", category: .appCaches, patterns: ["~/Library/Caches/SparseDir"])
        ])
        let scan = CategoryDetector.scan(configuration: InventoryScanConfiguration(
            home: f.home.path, allowSystemLocations: false, includeExtendedRules: false, catalogURL: catalog
        ))
        let item = try XCTUnwrap(scan.files.first { $0.ruleID == "sparse-cache" })
        XCTAssertEqual(item.allocatedBytes, 0, "Zero allocated blocks must remain 0 B, never replaced with logical size")
        XCTAssertEqual(item.logicalBytes, 1_048_576)
    }
}
