import XCTest
import SwiftUI
import AppKit
@testable import BrisaApp
@testable import BrisaCore

@MainActor
final class BrandIdentityTests: XCTestCase {
    func testBrandAssetsLoadWithExpectedRepsAndTemplateFlags() throws {
        // Isotipo PDFs across all variants
        for variant in [BrandAssetVariant.color, .light, .dark, .monochrome] {
            let image = try XCTUnwrap(BrandAssetCatalog.isotipoImage(variant: variant), "Missing isotipo \(variant.rawValue)")
            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertEqual(image.isTemplate, variant == .monochrome)
        }

        // Lockup PDFs across all variants
        for variant in [BrandAssetVariant.color, .colorDark, .light, .dark, .monochrome] {
            let image = try XCTUnwrap(BrandAssetCatalog.lockupImage(variant: variant), "Missing lockup \(variant.rawValue)")
            XCTAssertGreaterThan(image.size.width, image.size.height)
            XCTAssertEqual(image.isTemplate, variant == .monochrome)
        }

        // Menu bar template asset must provide 18x18 @1x and 36x36 @2x with alpha transparency and template tinting
        let menuBar = try XCTUnwrap(BrandAssetCatalog.menuBarTemplateImage(), "Missing menu bar template icon")
        XCTAssertTrue(menuBar.isTemplate)
        XCTAssertEqual(menuBar.size, NSSize(width: 18, height: 18))
        let bitmapReps = menuBar.representations.compactMap { $0 as? NSBitmapImageRep }
        XCTAssertEqual(Set(bitmapReps.map(\.pixelsWide)), Set([18, 36]))
        for rep in bitmapReps {
            XCTAssertEqual(rep.size, NSSize(width: 18, height: 18))
            XCTAssertTrue(rep.hasAlpha)
            // Corner pixel must be transparent (no filled background square), center must contain glyph ink
            let cornerAlpha = rep.colorAt(x: 0, y: 0)?.alphaComponent ?? -1
            XCTAssertEqual(cornerAlpha, 0, accuracy: 0.01)
            let midInk = (0..<rep.pixelsWide).contains { x in
                (rep.colorAt(x: x, y: rep.pixelsHigh / 2)?.alphaComponent ?? 0) > 0.4
            }
            XCTAssertTrue(midInk, "Menu bar rep \(rep.pixelsWide)px should have non-empty ink")
        }

        // Support illustrations in Light & Dark
        for scheme in [ColorScheme.light, .dark] {
            let welcome = try XCTUnwrap(BrandAssetCatalog.illustrationImage(.welcome, colorScheme: scheme))
            let empty = try XCTUnwrap(BrandAssetCatalog.illustrationImage(.emptyState, colorScheme: scheme))
            XCTAssertGreaterThan(welcome.size.width, welcome.size.height)
            XCTAssertGreaterThan(empty.size.width, 0)
        }
    }

    func testBrandViewsRenderAcrossLightDarkAndLanguages() async throws {
        let prevLang = UserDefaults.standard.string(forKey: "BrisaLanguage") ?? AppLanguage.system.rawValue
        defer { L10n.setPreference(prevLang) }

        let tempRoot = URL(fileURLWithPath: "/tmp").appendingPathComponent("brisa-brand-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let suiteName = "dev.brisa.brand.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = AppState(
            userDefaults: defaults,
            storeURL: tempRoot.appendingPathComponent("state"),
            ipcSocketPath: nil,
            homeDirectory: tempRoot.path,
            startServices: false
        )
        defer { state.shutdown() }

        let liveMetrics = LiveMetricsStore(observeLifecycle: false)
        defer { liveMetrics.shutdown() }

        let scratchDir = ProcessInfo.processInfo.environment["BRISA_RENDER_SCRATCH_DIR"]

        @discardableResult
        func capture<V: View>(_ view: V, width: CGFloat, height: CGFloat? = nil, appearance: NSAppearance.Name, filename: String) throws -> NSSize {
            let host = NSHostingView(rootView: view)
            host.appearance = NSAppearance(named: appearance)
            let fitting = host.fittingSize
            let targetSize = NSSize(
                width: width > 0 ? width : max(24, ceil(fitting.width)),
                height: height ?? max(24, ceil(fitting.height))
            )
            host.frame = NSRect(origin: .zero, size: targetSize)
            host.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            if let scratchDir {
                let dir = URL(fileURLWithPath: scratchDir)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                try png.write(to: dir.appendingPathComponent(filename))
            }
            return targetSize
        }

        // Welcome & Main Window (Overview Empty + Sidebar) in ES Light and EN Dark
        L10n.setPreference("es")
        let welcomeES = try capture(
            WelcomeView()
                .environmentObject(state)
                .frame(width: 960, height: 680)
                .background(Palette.background)
                .environment(\.locale, Locale(identifier: "es")),
            width: 960, height: 680,
            appearance: .aqua,
            filename: "brand-welcome-es-light.png"
        )
        XCTAssertEqual(welcomeES.width, 960)

        L10n.setPreference("en")
        let welcomeENDark = try capture(
            WelcomeView()
                .environmentObject(state)
                .frame(width: 960, height: 680)
                .background(Palette.background)
                .preferredColorScheme(.dark)
                .environment(\.locale, Locale(identifier: "en")),
            width: 960, height: 680,
            appearance: .darkAqua,
            filename: "brand-welcome-en-dark.png"
        )
        XCTAssertEqual(welcomeENDark.width, 960)

        // Complete onboarding -> Main RootView (Sidebar BrandMark + Empty Findings) Light ES & Dark EN
        state.completeWelcome()
        state.page = .findings

        L10n.setPreference("es")
        _ = try capture(
            RootView()
                .environmentObject(state)
                .environmentObject(liveMetrics)
                .frame(width: 1080, height: 720)
                .environment(\.locale, Locale(identifier: "es")),
            width: 1080, height: 720,
            appearance: .aqua,
            filename: "brand-root-findings-es-light.png"
        )

        L10n.setPreference("en")
        _ = try capture(
            RootView()
                .environmentObject(state)
                .environmentObject(liveMetrics)
                .frame(width: 1080, height: 720)
                .preferredColorScheme(.dark)
                .environment(\.locale, Locale(identifier: "en")),
            width: 1080, height: 720,
            appearance: .darkAqua,
            filename: "brand-root-findings-en-dark.png"
        )

        // Lockup Light & Dark + MenuBar Icon-only & With-GB
        L10n.setPreference("es")
        _ = try capture(
            HStack(spacing: 24) {
                BrandLockup(height: 36)
                BrandMark(size: 36)
            }
            .padding(16)
            .background(Palette.background),
            width: 320,
            appearance: .aqua,
            filename: "brand-lockup-light.png"
        )

        _ = try capture(
            HStack(spacing: 24) {
                BrandLockup(height: 36)
                BrandMark(size: 36)
            }
            .padding(16)
            .background(Palette.background)
            .preferredColorScheme(.dark),
            width: 320,
            appearance: .darkAqua,
            filename: "brand-lockup-dark.png"
        )

        let sampled = await liveMetrics.sample()
        XCTAssertNotNil(sampled.diskFree)

        // Popover MenuPanel Light ES & Dark EN
        L10n.setPreference("es")
        _ = try capture(
            MenuPanel()
                .environmentObject(state)
                .environment(\.locale, Locale(identifier: "es")),
            width: 392,
            appearance: .aqua,
            filename: "brand-popover-es-light.png"
        )

        L10n.setPreference("en")
        _ = try capture(
            MenuPanel()
                .environmentObject(state)
                .preferredColorScheme(.dark)
                .environment(\.locale, Locale(identifier: "en")),
            width: 392,
            appearance: .darkAqua,
            filename: "brand-popover-en-dark.png"
        )
    }
}
