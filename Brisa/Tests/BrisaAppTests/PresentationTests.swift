import XCTest
import AppKit
import SwiftUI
import BrisaCore
@testable import BrisaApp

final class PresentationTests: XCTestCase {
    func testDiskSegmentsKeepTinyReviewableFractionAndExactTotal() throws {
        let usage = try XCTUnwrap(MenuDiskUsage(totalBytes: 1_000_000, freeBytes: 250_000,
            scannedBytes: 100_000, eligibleBytes: 1))
        XCTAssertEqual(usage.other + usage.scanned + usage.eligible, usage.used)
        XCTAssertEqual(usage.fraction(usage.eligible), 0.000001, accuracy: 1e-12)
        XCTAssertEqual(usage.fraction(usage.other) + usage.fraction(usage.scanned)
            + usage.fraction(usage.eligible), 0.75, accuracy: 1e-12)
    }

    func testDiskSegmentsCannotInventReviewableDataOutsideMeasuredBytes() throws {
        let usage = try XCTUnwrap(MenuDiskUsage(totalBytes: 100, freeBytes: 20,
            scannedBytes: 10, eligibleBytes: 50))
        XCTAssertEqual(usage.eligible, 10)
        XCTAssertEqual(usage.scanned, 0)
        XCTAssertEqual(usage.other, 70)
    }

    func testDiskUnavailableAndBoundaryValuesStayFinite() throws {
        for free in [Int64.min, -1, 101] {
            XCTAssertNil(MenuDiskUsage(totalBytes: 100, freeBytes: free, scannedBytes: 0, eligibleBytes: 0))
        }
        XCTAssertNil(MenuDiskUsage(totalBytes: nil, freeBytes: 0, scannedBytes: 0, eligibleBytes: 0))
        XCTAssertNil(MenuDiskUsage(totalBytes: 0, freeBytes: 0, scannedBytes: 0, eligibleBytes: 0))
        let usage = try XCTUnwrap(MenuDiskUsage(totalBytes: Int64.max, freeBytes: 0,
            scannedBytes: Int64.max, eligibleBytes: Int64.max))
        XCTAssertEqual(usage.fraction(usage.used), 1)
        XCTAssertEqual(usage.other, 0)
    }

    func testAppearanceUnknownValuesFallBackToSystem() {
        XCTAssertEqual(AppAppearance.normalized(nil), "system")
        XCTAssertEqual(AppAppearance.normalized("invalid"), "system")
        XCTAssertEqual(AppAppearance.normalized("light"), "light")
        XCTAssertEqual(AppAppearance.normalized("dark"), "dark")
        XCTAssertNil(AppAppearance.system.colorScheme)
        XCTAssertNotNil(AppAppearance.light.colorScheme)
        XCTAssertNotNil(AppAppearance.dark.colorScheme)
    }

    func testSparseInventoryPresentationKeepsZeroAllocatedBytes() {
        let file = IndexedFile(id: "sparse", path: "/Users/test/Library/Caches/disk.raw", root: "/Users/test",
            identity: FileIdentity(device: 1, inode: 1, size: 1_000_000, modified: 1, changed: 1),
            allocatedBytes: 0, category: .other, modifiedAt: Date(timeIntervalSince1970: 1),
            eligible: false, reason: "inventory_only", confidence: "inventory", logicalBytes: 1_000_000)
        let presentation = InventoryItemPresentation(file: file)
        XCTAssertEqual(presentation.size, "0 B")
        XCTAssertFalse(presentation.selectable)
        XCTAssertEqual(presentation.name, "disk.raw")
    }

    func testRegenerationGuidanceAdaptsToFamilyAndBehavior() {
        let baseIdentity = FileIdentity(device: 1, inode: 2, size: 1024, modified: 1, changed: 1)

        let rebuildsItem = IndexedFile(
            id: "derived", path: "/Users/test/Library/Developer/Xcode/DerivedData/App", root: "/Users/test",
            identity: baseIdentity, allocatedBytes: 1024, category: .cache, modifiedAt: Date(),
            eligible: true, reason: "eligible", confidence: "high",
            storageCategory: .developerCaches, sourceGroup: "Xcode build data", regenBehavior: "rebuilds"
        )
        let rebuildsGuidance = RegenerationGuidance.describe(for: rebuildsItem)
        XCTAssertEqual(rebuildsGuidance.behavior, .rebuilds)
        XCTAssertTrue(rebuildsGuidance.familyTitleEN.contains("Xcode"))

        let installerGone = IndexedFile(
            id: "dmg", path: "/Users/test/Downloads/Tool.dmg", root: "/Users/test",
            identity: baseIdentity, allocatedBytes: 1024, category: .other, modifiedAt: Date(),
            eligible: true, reason: "eligible", confidence: "high",
            storageCategory: .downloadsAndInstallers, sourceGroup: "Downloads and installers", regenBehavior: "gone"
        )
        let installerDownloads = IndexedFile(
            id: "pkg", path: "/Users/test/Downloads/Tool.pkg", root: "/Users/test",
            identity: baseIdentity, allocatedBytes: 1024, category: .other, modifiedAt: Date(),
            eligible: true, reason: "eligible", confidence: "high",
            storageCategory: .downloadsAndInstallers, sourceGroup: "Downloads and installers", regenBehavior: "downloads"
        )
        let goneGuidance = RegenerationGuidance.describe(for: installerGone)
        let dlGuidance = RegenerationGuidance.describe(for: installerDownloads)
        XCTAssertEqual(goneGuidance.behavior, .gone)
        XCTAssertEqual(dlGuidance.behavior, .downloads)
        XCTAssertNotEqual(goneGuidance.regenerationEN, dlGuidance.regenerationEN)

        // Fallback works cleanly when sourceGroup and regenBehavior are nil.
        let generic = IndexedFile(
            id: "generic", path: "/Users/test/Library/Caches/custom", root: "/Users/test",
            identity: baseIdentity, allocatedBytes: 512, category: .cache, modifiedAt: Date(),
            eligible: false, reason: "view_only", confidence: "inventory",
            storageCategory: .appCaches, sourceGroup: nil, dataKind: .regenerable, regenBehavior: nil
        )
        let fallback = RegenerationGuidance.describe(for: generic)
        XCTAssertEqual(fallback.behavior, .rebuilds)
        XCTAssertFalse(fallback.whatIsLostES.isEmpty)
    }

    @MainActor func testMenuBarPreferenceIsolationAndEntrega1ViewsRenderLightAndDark() async throws {
        defer { L10n.setPreference("en") }
        let fm = FileManager.default
        let resolvedTemp = try Paths.systemLocation(fm.temporaryDirectory.path)
        let tempRoot = URL(fileURLWithPath: resolvedTemp).appendingPathComponent("brisa-ui-test-\(UUID().uuidString)")
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }
        let storeDir = tempRoot.appendingPathComponent("state")

        let suiteName = "dev.brisa.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = AppState(
            userDefaults: defaults,
            storeURL: storeDir,
            ipcSocketPath: nil,
            homeDirectory: tempRoot.path,
            startServices: false
        )
        defer { state.shutdown() }

        XCTAssertFalse(state.showMenuBarFreeSpace)
        state.showMenuBarFreeSpace = true
        XCTAssertTrue(defaults.bool(forKey: "BrisaShowMenuBarFreeSpace"))

        let store = try PrivateStore(directory: storeDir)
        let persisted = try store.read("preferences.json", as: Preferences.self)
        XCTAssertEqual(persisted?.showMenuBarFreeSpace, true)

        let liveMetrics = LiveMetricsStore(observeLifecycle: false)
        defer { liveMetrics.shutdown() }
        let sampled = await liveMetrics.sample()
        XCTAssertNotNil(sampled.diskFree)

        let sampleFile = IndexedFile(
            id: "xcode-sample",
            path: tempRoot.path + "/Library/Developer/Xcode/DerivedData/DemoApp",
            root: tempRoot.path,
            identity: FileIdentity(device: 1, inode: 42, size: 128_000_000, modified: 1, changed: 1),
            allocatedBytes: 128_000_000,
            category: .cache,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            eligible: true,
            reason: "eligible",
            confidence: "high",
            storageCategory: .developerCaches,
            sourceGroup: "Xcode build data",
            dataKind: .regenerable,
            regenBehavior: "rebuilds"
        )

        let scratchDir = ProcessInfo.processInfo.environment["BRISA_RENDER_SCRATCH_DIR"]

        func renderAndMeasure<V: View>(_ view: V, width: CGFloat, appearance: NSAppearance.Name, filename: String) throws -> CGSize {
            let hosting = NSHostingView(rootView: view)
            hosting.appearance = NSAppearance(named: appearance)
            let targetWidth = max(width, hosting.fittingSize.width)
            let fitting = hosting.fittingSize
            let targetHeight = max(fitting.height, 20)
            hosting.frame = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
            hosting.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(targetWidth, 0)
            XCTAssertGreaterThan(targetHeight, 0)

            if let scratchDir {
                let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: scratchDir).appendingPathComponent(filename))
            }
            return CGSize(width: targetWidth, height: targetHeight)
        }

        // Verify menu bar icon-only vs explicit GB text label layout.
        L10n.setPreference("en")
        let iconOnly = try renderAndMeasure(
            MenuBarStatusLabel(showFreeSpace: false, language: "en", liveMetrics: liveMetrics)
                .padding(6)
                .background(Palette.sidebar),
            width: 0,
            appearance: .aqua,
            filename: "menubar-icon-only.png"
        )
        let withFreeGB = try renderAndMeasure(
            MenuBarStatusLabel(showFreeSpace: true, language: "en", liveMetrics: liveMetrics)
                .padding(6)
                .background(Palette.sidebar),
            width: 0,
            appearance: .aqua,
            filename: "menubar-with-gb-light.png"
        )
        let withFreeGBDark = try renderAndMeasure(
            MenuBarStatusLabel(showFreeSpace: true, language: "es", liveMetrics: liveMetrics)
                .padding(6)
                .background(Color(NSColor(srgbRed: 0.14, green: 0.14, blue: 0.16, alpha: 1)))
                .preferredColorScheme(.dark),
            width: 0,
            appearance: .darkAqua,
            filename: "menubar-with-gb-dark.png"
        )
        XCTAssertGreaterThan(withFreeGB.width, iconOnly.width)
        XCTAssertGreaterThan(withFreeGBDark.width, iconOnly.width)

        // Expanded InventoryItemDetails in ES & EN across Light & Dark modes.
        L10n.setPreference("es")
        let detailsESLight = try renderAndMeasure(
            InventoryItemDetails(file: sampleFile, actionsEnabled: true, reveal: {}, focusMap: {}, protect: {})
                .frame(width: 720)
                .background(Palette.background)
                .environment(\.locale, Locale(identifier: "es")),
            width: 720,
            appearance: .aqua,
            filename: "details-es-light.png"
        )
        XCTAssertGreaterThan(detailsESLight.height, 140)

        L10n.setPreference("en")
        let detailsENDark = try renderAndMeasure(
            InventoryItemDetails(file: sampleFile, actionsEnabled: true, reveal: {}, focusMap: {}, protect: {})
                .frame(width: 720)
                .background(Palette.background)
                .preferredColorScheme(.dark)
                .environment(\.locale, Locale(identifier: "en")),
            width: 720,
            appearance: .darkAqua,
            filename: "details-en-dark.png"
        )
        XCTAssertGreaterThan(detailsENDark.height, 140)

        let settingsSize = try renderAndMeasure(
            SettingsView()
                .environmentObject(state)
                .frame(width: 820)
                .background(Palette.background)
                .preferredColorScheme(.dark)
                .environment(\.locale, Locale(identifier: "en")),
            width: 820,
            appearance: .darkAqua,
            filename: "settings-en-dark.png"
        )
        XCTAssertGreaterThan(settingsSize.height, 260)
    }
}
