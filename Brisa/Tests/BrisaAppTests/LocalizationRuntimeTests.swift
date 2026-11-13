import XCTest
import BrisaCore
@testable import BrisaApp

final class LocalizationRuntimeTests: XCTestCase {
    private var previousPreference: String = AppLanguage.system.rawValue

    override func setUp() {
        super.setUp()
        previousPreference = L10n.currentPreference
    }

    override func tearDown() {
        L10n.setPreference(previousPreference)
        super.tearDown()
    }

    func testRuntimeLanguageSwitchingResolvesModularStringsWithoutRestart() {
        L10n.setPreference("es")
        XCTAssertEqual(L10n.code, "es")
        XCTAssertEqual(L10n.Common.navOverview, "Inicio")
        XCTAssertEqual(L10n.MenuBar.metricMemory, "Memoria")
        XCTAssertEqual(L10n.MenuBar.breakdownOtherLabel, "Otros")
        XCTAssertEqual(L10n.Settings.languageTitle, "Idioma")
        XCTAssertEqual(L10n.Overview.title, "Inicio")
        XCTAssertEqual(L10n.bilingual(es: "Hola", en: "Hello"), "Hola")

        L10n.setPreference("en")
        XCTAssertEqual(L10n.code, "en")
        XCTAssertEqual(L10n.Common.navOverview, "Home")
        XCTAssertEqual(L10n.MenuBar.metricMemory, "Memory")
        XCTAssertEqual(L10n.MenuBar.breakdownOtherLabel, "Other")
        XCTAssertEqual(L10n.Settings.languageTitle, "Language")
        XCTAssertEqual(L10n.Overview.title, "Home")
        XCTAssertEqual(L10n.bilingual(es: "Hola", en: "Hello"), "Hello")

        // Verify formatted lookups never return raw keys in either language.
        XCTAssertEqual(L10n.MenuBar.cpuCores(1), "1 core")
        XCTAssertEqual(L10n.MenuBar.cpuCores(10), "10 cores")
        XCTAssertEqual(L10n.MenuBar.breakdownProcessesShort(4), "4 proc.")
        XCTAssertFalse(L10n.MenuBar.breakdownCPUSubtitle(10).contains("breakdown."))
    }

    func testMetricsFormatAndLocaleSwitchImmediately() {
        L10n.setPreference("es")
        XCTAssertEqual(L10n.MenuBar.cpuCores(1), "1 núcleo")
        XCTAssertEqual(L10n.MenuBar.cpuCores(8), "8 núcleos")
        XCTAssertEqual(L10n.MenuBar.footerReviewCount(3), "Revisar (3)")

        L10n.setPreference("en")
        XCTAssertEqual(L10n.MenuBar.cpuCores(1), "1 core")
        XCTAssertEqual(L10n.MenuBar.cpuCores(8), "8 cores")
        XCTAssertEqual(L10n.MenuBar.footerReviewCount(3), "Review (3)")
    }

    func testMenuBarFreeSpaceAndRegenerationStringsResolveInESAndEN() {
        for lang in ["es", "en"] {
            L10n.setPreference(lang)
            XCTAssertFalse(L10n.MenuBar.statusBarFreeAccessibility("142 GB").contains("status_bar."))
            XCTAssertFalse(L10n.Settings.menuBarFreeSpaceTitle.contains("menu_bar_free_space."))
            XCTAssertFalse(L10n.Settings.menuBarFreeSpaceHint.contains("menu_bar_free_space."))
            XCTAssertFalse(L10n.Findings.rowGuidanceWhat.contains("row.guidance"))
            XCTAssertFalse(L10n.Findings.rowGuidanceLost.contains("row.guidance"))
            XCTAssertFalse(L10n.Findings.rowGuidanceRegen.contains("row.guidance"))
            XCTAssertFalse(L10n.Findings.rowRegenBehavior("rebuilds").contains("row.regen"))
            for behavior in RegenerationBehavior.allCases {
                XCTAssertFalse(L10n.Findings.regenBehaviorLabel(behavior).contains("row.regen."))
            }
        }
        L10n.setPreference("en")
    }
}
