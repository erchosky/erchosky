import BrisaCore
import Foundation

public enum L10nTable: String, CaseIterable {
    case common = "Common"
    case menuBar = "MenuBar"
    case overview = "Overview"
    case findings = "Findings"
    case appsAgents = "AppsAgents"
    case activity = "Activity"
    case settings = "Settings"
    case tools = "Tools"
}

/// Central modular localization gateway backed by `<lang>.lproj/*.strings` tables.
/// Switching language preference updates lookups immediately at runtime without restart.
enum L10n {
    private struct ActiveSnapshot {
        let preference: String
        let language: AppLanguage
        let locale: Locale
        let primaryTables: [L10nTable: [String: String]]
        let fallbackTables: [L10nTable: [String: String]]
        let primaryBundle: Bundle?
        let fallbackBundle: Bundle?
    }

    private static let lock = NSLock()
    private static var cachedBundles: [String: Bundle] = [:]
    private static var cachedParsedTables: [String: [L10nTable: [String: String]]] = [:]

    private static var resourceRootBundle: Bundle? = {
        ResourceBundleLocator.locate(named: "Brisa_BrisaApp") { Bundle.module }
    }()

    private static var snapshot: ActiveSnapshot = makeSnapshot(
        preference: AppLanguage.sanitizedPreference(UserDefaults.standard.string(forKey: "BrisaLanguage"))
    )

    static var currentPreference: String {
        lock.withLock { snapshot.preference }
    }

    static var activeLanguage: AppLanguage {
        lock.withLock { snapshot.language }
    }

    /// Concrete two-letter language code (`"es"` or `"en"`) for BrisaCore queries.
    static var code: String {
        activeLanguage.rawValue
    }

    static var locale: Locale {
        lock.withLock { snapshot.locale }
    }

    static func setPreference(_ raw: String) {
        let valid = AppLanguage.sanitizedPreference(raw)
        lock.withLock {
            if snapshot.preference == valid { return }
            snapshot = makeSnapshot(preference: valid)
        }
    }

    /// Convenience adapter for dynamic model metadata serialized as `(es, en)` in BrisaCore.
    static func bilingual(es: String, en: String) -> String {
        activeLanguage == .es ? es : en
    }

    static func tr(_ table: L10nTable, _ key: String) -> String {
        let snap = lock.withLock { snapshot }
        if let value = snap.primaryTables[table]?[key] {
            return value
        }
        if let bundle = snap.primaryBundle {
            let localized = bundle.localizedString(forKey: key, value: "__BRISA_MISSING__", table: table.rawValue)
            if localized != "__BRISA_MISSING__" {
                return localized
            }
        }
        if let value = snap.fallbackTables[table]?[key] {
            return value
        }
        if let bundle = snap.fallbackBundle {
            let localized = bundle.localizedString(forKey: key, value: "__BRISA_MISSING__", table: table.rawValue)
            if localized != "__BRISA_MISSING__" {
                return localized
            }
        }
        return key
    }

    static func fmt(_ table: L10nTable, _ key: String, _ args: CVarArg...) -> String {
        let snap = lock.withLock { snapshot }
        let template: String
        if let value = snap.primaryTables[table]?[key] {
            template = value
        } else if let bundle = snap.primaryBundle,
                  case let localized = bundle.localizedString(forKey: key, value: "__BRISA_MISSING__", table: table.rawValue),
                  localized != "__BRISA_MISSING__" {
            template = localized
        } else if let value = snap.fallbackTables[table]?[key] {
            template = value
        } else if let bundle = snap.fallbackBundle,
                  case let localized = bundle.localizedString(forKey: key, value: "__BRISA_MISSING__", table: table.rawValue),
                  localized != "__BRISA_MISSING__" {
            template = localized
        } else {
            template = key
        }
        return String(format: template, locale: snap.locale, arguments: args)
    }

    private static func makeSnapshot(preference: String) -> ActiveSnapshot {
        let lang = AppLanguage.resolve(preference: preference)
        let code = lang.rawValue
        let fallbackCode = AppLanguage.fallbackLanguage.rawValue
        let resolvedLocale = preference == AppLanguage.system.rawValue ? Locale.current : Locale(identifier: code)
        let primaryBundle = bundleLocked(for: code)
        let fallbackBundle = code == fallbackCode ? primaryBundle : bundleLocked(for: fallbackCode)
        let primaryTables = tablesLocked(for: code, bundle: primaryBundle)
        let fallbackTables = code == fallbackCode ? primaryTables : tablesLocked(for: fallbackCode, bundle: fallbackBundle)
        return ActiveSnapshot(
            preference: preference,
            language: lang,
            locale: resolvedLocale,
            primaryTables: primaryTables,
            fallbackTables: fallbackTables,
            primaryBundle: primaryBundle,
            fallbackBundle: fallbackBundle
        )
    }

    private static func tablesLocked(for langCode: String, bundle: Bundle?) -> [L10nTable: [String: String]] {
        if let cached = cachedParsedTables[langCode] {
            return cached
        }
        var result: [L10nTable: [String: String]] = [:]
        if let bundle {
            for table in L10nTable.allCases {
                if let url = bundle.url(forResource: table.rawValue, withExtension: "strings"),
                   let data = try? Data(contentsOf: url),
                   let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String] {
                    result[table] = plist
                }
            }
        }
        cachedParsedTables[langCode] = result
        return result
    }

    private static func bundleLocked(for langCode: String) -> Bundle? {
        if let cached = cachedBundles[langCode] {
            return cached
        }
        guard let root = resourceRootBundle else { return nil }
        if let lprojURL = root.url(forResource: langCode, withExtension: "lproj"),
           let loaded = Bundle(url: lprojURL) {
            cachedBundles[langCode] = loaded
            return loaded
        }
        if let path = root.path(forResource: langCode, ofType: "lproj"),
           let loaded = Bundle(path: path) {
            cachedBundles[langCode] = loaded
            return loaded
        }
        return nil
    }
}

// MARK: - Common

extension L10n {
    enum Common {
        static var navOverview: String { L10n.tr(.common, "nav.overview") }
        static var navFindings: String { L10n.tr(.common, "nav.findings") }
        static var navTools: String { L10n.tr(.common, "nav.tools") }
        static var navApplications: String { L10n.tr(.common, "nav.applications") }
        static var navAgents: String { L10n.tr(.common, "nav.agents") }
        static var navActivity: String { L10n.tr(.common, "nav.activity") }
        static var navSettings: String { L10n.tr(.common, "nav.settings") }

        static var appearanceSystem: String { L10n.tr(.common, "appearance.system") }
        static var appearanceLight: String { L10n.tr(.common, "appearance.light") }
        static var appearanceDark: String { L10n.tr(.common, "appearance.dark") }

        static var actionScan: String { L10n.tr(.common, "action.scan") }
        static var actionCancel: String { L10n.tr(.common, "action.cancel") }
        static var actionCloseNotice: String { L10n.tr(.common, "action.close_notice") }
        static var actionShowInFinder: String { L10n.tr(.common, "action.show_in_finder") }
        static var actionAuthorizeFolder: String { L10n.tr(.common, "action.authorize_folder") }
        static var actionProtect: String { L10n.tr(.common, "action.protect") }
        static var actionRemove: String { L10n.tr(.common, "action.remove") }

        static var liveBadge: String { L10n.tr(.common, "live.badge") }
        static var liveHelp: String { L10n.tr(.common, "live.help") }
        static var systemMacOS: String { L10n.tr(.common, "system.macos") }

        static var stateNormal: String { L10n.tr(.common, "state.normal") }
        static var stateElevated: String { L10n.tr(.common, "state.elevated") }
        static var stateWarning: String { L10n.tr(.common, "state.warning") }
        static var stateCritical: String { L10n.tr(.common, "state.critical") }
        static var stateNoData: String { L10n.tr(.common, "state.no_data") }
        static var stateUnavailable: String { L10n.tr(.common, "state.unavailable") }
        static var stateUnknown: String { L10n.tr(.common, "state.unknown") }
        static var stateUnknownFem: String { L10n.tr(.common, "state.unknown_fem") }
        static var statePartial: String { L10n.tr(.common, "state.partial") }
        static var statePending: String { L10n.tr(.common, "state.pending") }
        static var stateScanning: String { L10n.tr(.common, "state.scanning") }
        static var stateMeasured: String { L10n.tr(.common, "state.measured") }
        static var stateNotScanned: String { L10n.tr(.common, "state.not_scanned") }
        static var stateNoLocations: String { L10n.tr(.common, "state.no_locations") }
        static var stateNoAccess: String { L10n.tr(.common, "state.no_access") }
        static var stateNoItems: String { L10n.tr(.common, "state.no_items") }
        static var stateNoItemsDetected: String { L10n.tr(.common, "state.no_items_detected") }

        static func itemCount(_ count: Int) -> String {
            L10n.fmt(.common, count == 1 ? "count.item_singular" : "count.item_plural", count)
        }
        static func logicalShort(_ formatted: String) -> String {
            L10n.fmt(.common, "unit.logical_short_format", formatted)
        }
        static func sizePartial(_ formatted: String) -> String {
            L10n.fmt(.common, "unit.size_partial_format", formatted)
        }
        static var timeJustNow: String { L10n.tr(.common, "time.just_now") }
        static func timeMinutesAgo(_ minutes: Int) -> String {
            L10n.fmt(.common, "time.minutes_ago_format", minutes)
        }
        static func timeHoursAgo(_ hours: Int) -> String {
            L10n.fmt(.common, "time.hours_ago_format", hours)
        }

        static var categorySubCaches: String { L10n.tr(.common, "category.sub_caches") }
        static var categorySubLogs: String { L10n.tr(.common, "category.sub_logs") }
        static var categorySubOtherMeasured: String { L10n.tr(.common, "category.sub_other_measured") }
        static func aboutCategory(_ title: String) -> String {
            L10n.fmt(.common, "category.about_prefix_format", title)
        }

        static var eligibilityPartialLocked: String { L10n.tr(.common, "eligibility.partial_locked") }
        static var eligibilityVerifiedEligible: String { L10n.tr(.common, "eligibility.verified_eligible") }
        static var eligibilityInventoryOnly: String { L10n.tr(.common, "eligibility.inventory_only") }
        static var eligibilityNeverDelete: String { L10n.tr(.common, "eligibility.never_delete") }
        static var eligibilityInUseLocked: String { L10n.tr(.common, "eligibility.in_use_locked") }
        static var eligibilityRecentKeep: String { L10n.tr(.common, "eligibility.recent_keep") }
        static var eligibilityUnverifiedCondition: String { L10n.tr(.common, "eligibility.unverified_condition") }
        static var eligibilityManualInspection: String { L10n.tr(.common, "eligibility.manual_inspection") }

        static var reasonOrphanDetector: String { L10n.tr(.common, "eligibility.reason.orphan_detector") }
        static var reasonVerifiedIdleFile: String { L10n.tr(.common, "eligibility.reason.verified_idle_file") }
        static var reasonListOnly: String { L10n.tr(.common, "eligibility.reason.list_only") }
        static var reasonNeverDelete: String { L10n.tr(.common, "eligibility.reason.never_delete") }
        static var reasonExternalCommand: String { L10n.tr(.common, "eligibility.reason.external_command") }
        static var reasonUnverifiedCondition: String { L10n.tr(.common, "eligibility.reason.unverified_condition") }
        static var reasonInUse: String { L10n.tr(.common, "eligibility.reason.in_use") }
        static var reasonDirectory: String { L10n.tr(.common, "eligibility.reason.directory") }
        static var reasonRecent: String { L10n.tr(.common, "eligibility.reason.recent") }
        static var reasonOpenOrOutside: String { L10n.tr(.common, "eligibility.reason.open_or_outside") }
        static var reasonDefaultInventory: String { L10n.tr(.common, "eligibility.reason.default_inventory") }

        static var usageVerifiedIdle: String { L10n.tr(.common, "usage.verified_idle") }
        static var usageRecent: String { L10n.tr(.common, "usage.recent") }
        static var usageActiveProcess: String { L10n.tr(.common, "usage.active_process") }
        static var usageOpenDescriptor: String { L10n.tr(.common, "usage.open_descriptor") }
        static var usageNotChecked: String { L10n.tr(.common, "usage.not_checked") }
        static var usageUnknown: String { L10n.tr(.common, "usage.unknown") }

        static var usageDetailNotChecked: String { L10n.tr(.common, "usage.detail.not_checked") }
        static var usageDetailUnavailable: String { L10n.tr(.common, "usage.detail.unavailable") }
        static var usageDetailActiveAgent: String { L10n.tr(.common, "usage.detail.active_agent") }

        static var tierRegenerable: String { L10n.tr(.common, "tier.regenerable") }
        static var tierCostly: String { L10n.tr(.common, "tier.costly") }
        static var tierUserData: String { L10n.tr(.common, "tier.user_data") }
        static var tierNeverDelete: String { L10n.tr(.common, "tier.never_delete") }

        static var dateBasisFolder: String { L10n.tr(.common, "date_basis.folder") }
        static var dateBasisFile: String { L10n.tr(.common, "date_basis.file") }
        static var dateBasisDefault: String { L10n.tr(.common, "date_basis.default") }

        static var journalTrashed: String { L10n.tr(.common, "journal.trashed") }
        static var journalRestored: String { L10n.tr(.common, "journal.restored") }
        static var journalPlanned: String { L10n.tr(.common, "journal.planned") }
        static var journalCompleted: String { L10n.tr(.common, "journal.completed") }
        static var journalFailed: String { L10n.tr(.common, "journal.failed") }
        static var journalPartial: String { L10n.tr(.common, "journal.partial") }
        static var journalRejected: String { L10n.tr(.common, "journal.rejected") }
        static var journalCancelled: String { L10n.tr(.common, "journal.cancelled") }
        static var journalRetained: String { L10n.tr(.common, "journal.retained") }
        static var journalMoveUnconfirmed: String { L10n.tr(.common, "journal.move_unconfirmed") }
        static var journalRestoreUnconfirmed: String { L10n.tr(.common, "journal.restore_unconfirmed") }
        static var journalUnknown: String { L10n.tr(.common, "journal.unknown") }

        static var worktreeCleanIdle: String { L10n.tr(.common, "worktree.clean_idle") }
        static var worktreeDirty: String { L10n.tr(.common, "worktree.dirty") }
        static var worktreeUnpushed: String { L10n.tr(.common, "worktree.unpushed") }
        static var worktreeLocked: String { L10n.tr(.common, "worktree.locked") }
        static var worktreeInUse: String { L10n.tr(.common, "worktree.in_use") }
        static var worktreeRecent: String { L10n.tr(.common, "worktree.recent") }
        static var worktreeMissing: String { L10n.tr(.common, "worktree.missing") }
        static var worktreeUnknown: String { L10n.tr(.common, "worktree.unknown") }
    }
}

// MARK: - MenuBar

extension L10n {
    enum MenuBar {
        static var headerReady: String { L10n.tr(.menuBar, "header.ready") }
        static var headerPromptScan: String { L10n.tr(.menuBar, "header.prompt_scan") }

        static var metricMemory: String { L10n.tr(.menuBar, "metric.memory") }
        static var metricCPU: String { L10n.tr(.menuBar, "metric.cpu") }
        static var metricGPU: String { L10n.tr(.menuBar, "metric.gpu") }
        static var metricSampling: String { L10n.tr(.menuBar, "metric.sampling") }
        static func physicalRAM(_ formatted: String) -> String { L10n.fmt(.menuBar, "metric.physical_ram_format", formatted) }
        static func ramRatio(_ used: String, _ total: String) -> String { L10n.fmt(.menuBar, "metric.ram_ratio_format", used, total) }
        static func cpuCores(_ count: Int) -> String {
            L10n.fmt(.menuBar, count == 1 ? "metric.cpu_cores_singular" : "metric.cpu_cores_plural", count)
        }
        static func gpuVRAM(_ formatted: String) -> String { L10n.fmt(.menuBar, "metric.gpu_vram_format", formatted) }
        static func gpuRenderer(_ percent: Int) -> String { L10n.fmt(.menuBar, "metric.gpu_renderer_format", percent) }
        static var metricMemoryPressure: String { L10n.tr(.menuBar, "metric.memory_pressure") }
        static var metricMemoryPressureShort: String { L10n.tr(.menuBar, "metric.memory_pressure_short") }

        static var diskFree: String { L10n.tr(.menuBar, "disk.free") }
        static func diskUsedRatio(_ used: String, _ total: String) -> String { L10n.fmt(.menuBar, "disk.used_ratio_format", used, total) }
        static var diskScanned: String { L10n.tr(.menuBar, "disk.scanned") }
        static var diskReviewable: String { L10n.tr(.menuBar, "disk.reviewable") }
        static var diskVolumeUsage: String { L10n.tr(.menuBar, "disk.volume_usage") }
        static func diskAccessibilityValue(_ free: String, _ used: String, _ total: String) -> String {
            L10n.fmt(.menuBar, "disk.accessibility_value_format", free, used, total)
        }
        static var diskHelp: String { L10n.tr(.menuBar, "disk.help") }

        static var categoriesTitle: String { L10n.tr(.menuBar, "categories.title") }
        static var categoriesFooterNote: String { L10n.tr(.menuBar, "categories.footer_note") }
        static var categoriesScanningState: String { L10n.tr(.menuBar, "categories.scanning_state") }
        static var categoriesNeedsRefresh: String { L10n.tr(.menuBar, "categories.needs_refresh") }
        static var categoriesRequiresAuth: String { L10n.tr(.menuBar, "categories.requires_authorization") }
        static var categoriesNoLocations: String { L10n.tr(.menuBar, "categories.no_locations_found") }
        static func categoryPartialSuffix(_ size: String) -> String { L10n.fmt(.menuBar, "categories.partial_suffix_format", size) }
        static func categoryItemShort(_ count: Int) -> String { L10n.fmt(.menuBar, "categories.item_short_format", count) }

        static func footerReviewCount(_ count: Int) -> String { L10n.fmt(.menuBar, "footer.review_count_format", count) }
        static var footerReview: String { L10n.tr(.menuBar, "footer.review") }
        static func footerAppearance(_ name: String) -> String { L10n.fmt(.menuBar, "footer.appearance_prefix_format", name) }
        static var footerChangeAppearance: String { L10n.tr(.menuBar, "footer.change_appearance") }
        static func footerLanguage(_ name: String) -> String { L10n.fmt(.menuBar, "footer.language_prefix_format", name) }
        static var footerChangeLanguage: String { L10n.tr(.menuBar, "footer.change_language") }
        static var footerOpenMainWindow: String { L10n.tr(.menuBar, "footer.open_main_window") }
        static var footerSettings: String { L10n.tr(.menuBar, "footer.settings") }
        static var footerQuit: String { L10n.tr(.menuBar, "footer.quit") }

        static var breakdownMemoryTitle: String { L10n.tr(.menuBar, "breakdown.title.memory") }
        static var breakdownCPUTitle: String { L10n.tr(.menuBar, "breakdown.title.cpu") }
        static var breakdownGPUTitle: String { L10n.tr(.menuBar, "breakdown.title.gpu") }
        static var breakdownSystemLabel: String { L10n.tr(.menuBar, "breakdown.system_label") }
        static var breakdownOtherLabel: String { L10n.tr(.menuBar, "breakdown.other_label") }
        static func breakdownProcessesShort(_ count: Int) -> String { L10n.fmt(.menuBar, "breakdown.processes_short_format", count) }
        static func breakdownMemorySubtitle(_ used: String, _ total: String) -> String {
            L10n.fmt(.menuBar, "breakdown.memory_subtitle_format", used, total)
        }
        static func breakdownCPUSubtitle(_ cores: Int) -> String {
            L10n.fmt(.menuBar, "breakdown.cpu_subtitle_format", cpuCores(cores))
        }
        static func breakdownGPUSubtitle(_ mem: String) -> String {
            L10n.fmt(.menuBar, "breakdown.gpu_subtitle_format", mem)
        }
        static var breakdownGPUSubtitlePlain: String { L10n.tr(.menuBar, "breakdown.gpu_subtitle_plain") }
        static var breakdownGPUWarmingUp: String { L10n.tr(.menuBar, "breakdown.gpu_warming_up") }
        static var breakdownGPUIdle: String { L10n.tr(.menuBar, "breakdown.gpu_idle") }
        static var breakdownGPUUnavailable: String { L10n.tr(.menuBar, "breakdown.gpu_unavailable") }
        static var breakdownCPUEmpty: String { L10n.tr(.menuBar, "breakdown.cpu_empty") }
        static var breakdownMemoryEmpty: String { L10n.tr(.menuBar, "breakdown.memory_empty") }
        static var breakdownMemoryRSSNote: String { L10n.tr(.menuBar, "breakdown.memory_rss_note") }
        static var breakdownCPUIntervalNote: String { L10n.tr(.menuBar, "breakdown.cpu_interval_note") }
        static var breakdownGPUShareNote: String { L10n.tr(.menuBar, "breakdown.gpu_share_note") }
        static func breakdownPercent(_ value: String) -> String { L10n.fmt(.menuBar, "breakdown.percent_format", value) }
        static func statusBarFreeAccessibility(_ size: String) -> String {
            L10n.fmt(.menuBar, "status_bar.free_accessibility_format", size)
        }
        static var navBack: String { L10n.tr(.menuBar, "nav.back") }
        static var navAllCategories: String { L10n.tr(.menuBar, "nav.all_categories") }
        static var navToolsSection: String { L10n.tr(.menuBar, "nav.tools_section") }
        static var navQuickActions: String { L10n.tr(.menuBar, "nav.quick_actions") }
        static func actionContinueReview(_ size: String) -> String {
            L10n.fmt(.menuBar, "action.continue_review", size)
        }
        static var actionSelectEligibleInCategory: String { L10n.tr(.menuBar, "action.select_eligible_in_category") }
        static var actionClearCategorySelection: String { L10n.tr(.menuBar, "action.clear_category_selection") }
        static func categoryItemsCount(_ total: Int, eligible: Int) -> String {
            L10n.fmt(.menuBar, "category.items_count_format", total, eligible)
        }
        static var categoryLockedShort: String { L10n.tr(.menuBar, "category.locked_short") }
        static var categoryExpandHint: String { L10n.tr(.menuBar, "category.expand_hint") }
        static var toolsProjectsShort: String { L10n.tr(.menuBar, "tools.projects_short") }
        static var toolsPackagesShort: String { L10n.tr(.menuBar, "tools.packages_short") }
        static var toolsDuplicatesShort: String { L10n.tr(.menuBar, "tools.duplicates_short") }
        static var toolsAppsShort: String { L10n.tr(.menuBar, "tools.apps_short") }
        static var toolsDockerShort: String { L10n.tr(.menuBar, "tools.docker_short") }
        static var planInlineTitle: String { L10n.tr(.menuBar, "plan.inline_title") }
        static var planExecuteNow: String { L10n.tr(.menuBar, "plan.execute_now") }
        static var planResultDone: String { L10n.tr(.menuBar, "plan.result_done") }

        static var headerScanPrompt: String { L10n.tr(.menuBar, "header.scan_prompt") }
        static var statusNotScanned: String { L10n.tr(.menuBar, "status.not_scanned") }
        static func statusScanningProgress(_ completed: Int) -> String {
            L10n.fmt(.menuBar, "status.scanning_progress_format", completed)
        }
        static var statusPartialWarning: String { L10n.tr(.menuBar, "status.partial_warning") }
        static var statusRefreshRecommended: String { L10n.tr(.menuBar, "status.refresh_recommended") }
        static var actionScanMac: String { L10n.tr(.menuBar, "action.scan_mac") }
        static var actionRescanMac: String { L10n.tr(.menuBar, "action.rescan_mac") }
        static func actionReviewCandidates(_ count: Int, _ size: String) -> String {
            L10n.fmt(.menuBar, count == 1 ? "action.review_candidate_singular_format" : "action.review_candidates_format", count, size)
        }
        static func actionReviewSelection(_ count: Int, _ size: String) -> String {
            L10n.fmt(.menuBar, "action.review_selection_format", count, size)
        }
        static var emptyAllClearTitle: String { L10n.tr(.menuBar, "empty.all_clear_title") }
        static var emptyAllClearSubtitle: String { L10n.tr(.menuBar, "empty.all_clear_subtitle") }
        static var entryExploreSpace: String { L10n.tr(.menuBar, "entry.explore_space") }
        static var entryExploreSpaceSubtitle: String { L10n.tr(.menuBar, "entry.explore_space_subtitle") }
        static var entryTools: String { L10n.tr(.menuBar, "entry.tools") }
        static var entryToolsSubtitle: String { L10n.tr(.menuBar, "entry.tools_subtitle") }
        static var sectionPerformance: String { L10n.tr(.menuBar, "section.performance") }
        static var candidatesTitle: String { L10n.tr(.menuBar, "candidates.title") }
        static var candidatesSubtitle: String { L10n.tr(.menuBar, "candidates.subtitle") }
        static var candidatesSelectAll: String { L10n.tr(.menuBar, "candidates.select_all") }
        static var candidatesClear: String { L10n.tr(.menuBar, "candidates.clear") }
        static var candidatesReviewPlan: String { L10n.tr(.menuBar, "candidates.review_plan") }
        static var exploreTitle: String { L10n.tr(.menuBar, "explore.title") }
        static var exploreNote: String { L10n.tr(.menuBar, "explore.note") }
        static var toolsEverydaySection: String { L10n.tr(.menuBar, "tools.everyday_section") }
        static var toolsAdvancedSection: String { L10n.tr(.menuBar, "tools.advanced_section") }
        static var toolsDuplicatesDesc: String { L10n.tr(.menuBar, "tools.duplicates_desc") }
        static var toolsAppsDesc: String { L10n.tr(.menuBar, "tools.apps_desc") }
        static var toolsProjectsDesc: String { L10n.tr(.menuBar, "tools.projects_desc") }
        static var toolsPackagesDesc: String { L10n.tr(.menuBar, "tools.packages_desc") }
        static var toolsDockerDesc: String { L10n.tr(.menuBar, "tools.docker_desc") }
        static var actionOpenWindowShort: String { L10n.tr(.menuBar, "action.open_window_short") }
    }
}

// MARK: - Overview

extension L10n {
    enum Overview {
        static var title: String { L10n.tr(.overview, "title") }
        static var scanningTitle: String { L10n.tr(.overview, "scanning_title") }
        static var refreshNeeded: String { L10n.tr(.overview, "refresh_needed") }
        static func scannedAgo(_ rel: String) -> String { L10n.fmt(.overview, "scanned_ago_format", rel) }
        static var partialBannerTitle: String { L10n.tr(.overview, "partial_banner_title") }
        static var details: String { L10n.tr(.overview, "details") }
        static var partialPopoverTitle: String { L10n.tr(.overview, "partial_popover_title") }
        static func partialPopoverCounts(_ size: String, _ count: Int) -> String {
            L10n.fmt(.overview, "partial_popover_counts_format", size, count)
        }
        static var partialPopoverBody: String { L10n.tr(.overview, "partial_popover_body") }
        static var accessNone: String { L10n.tr(.overview, "access_none") }
        static var accessPartial: String { L10n.tr(.overview, "access_partial") }
        static var cancelScan: String { L10n.tr(.overview, "cancel_scan") }

        static var sectionSpaceByCategory: String { L10n.tr(.overview, "section.space_by_category") }
        static var sectionMacPerformance: String { L10n.tr(.overview, "section.mac_performance") }
        static var sectionMoreSystemInfo: String { L10n.tr(.overview, "section.more_system_info") }

        static var cardFreeSpace: String { L10n.tr(.overview, "card.free_space") }
        static func cardOfCapacity(_ total: String) -> String { L10n.fmt(.overview, "card.of_capacity_format", total) }
        static var cardUsedLabel: String { L10n.tr(.overview, "card.used_label") }
        static var cardReviewable: String { L10n.tr(.overview, "card.reviewable") }
        static var cardScanToFind: String { L10n.tr(.overview, "card.scan_to_find") }
        static func selectableFiles(_ count: Int) -> String {
            L10n.fmt(.overview, count == 1 ? "card.selectable_singular" : "card.selectable_plural", count)
        }
        static var actionBrowseFiles: String { L10n.tr(.overview, "action.browse_files") }
        static var actionReviewFiles: String { L10n.tr(.overview, "action.review_files") }
        static func rowReviewableSuffix(_ size: String) -> String { L10n.fmt(.overview, "row.reviewable_suffix_format", size) }
        static var rowViewOnly: String { L10n.tr(.overview, "row.view_only") }

        static var tileCPUDetailSource: String { L10n.tr(.overview, "tile.cpu_detail_source") }
        static var tileRAMUsedCaps: String { L10n.tr(.overview, "tile.ram_used_caps") }
        static var tileRAMCaption: String { L10n.tr(.overview, "tile.ram_caption") }
        static var tileSwapCaption: String { L10n.tr(.overview, "tile.swap_caption") }
        static var tilePressureCaps: String { L10n.tr(.overview, "tile.pressure_caps") }
        static func tilePressureComp(_ formatted: String) -> String { L10n.fmt(.overview, "tile.pressure_comp_format", formatted) }
        static var tilePressureCaption: String { L10n.tr(.overview, "tile.pressure_caption") }
        static var tileSnapshotsCaps: String { L10n.tr(.overview, "tile.snapshots_caps") }
        static func tileSnapshotsCount(_ count: Int) -> String { L10n.fmt(.overview, "tile.snapshots_count_format", count) }
        static var tileSnapshotsCaption: String { L10n.tr(.overview, "tile.snapshots_caption") }
        static var tileGPUCaption: String { L10n.tr(.overview, "tile.gpu_caption") }

        static var healthRAMUsed: String { L10n.tr(.overview, "health.ram_used") }
        static var healthMemoryPressure: String { L10n.tr(.overview, "health.memory_pressure") }

        static var spaceMapTitle: String { L10n.tr(.overview, "spacemap.title") }
        static var spaceMapPartialMap: String { L10n.tr(.overview, "spacemap.partial_map") }
        static var spaceMapSyncedWithList: String { L10n.tr(.overview, "spacemap.synced_with_list") }
        static var spaceMapShowTiles: String { L10n.tr(.overview, "spacemap.show_tiles") }
        static var spaceMapAccessibleList: String { L10n.tr(.overview, "spacemap.accessible_list") }
        static func spaceMapAllocatedPrefix(_ text: String) -> String { L10n.fmt(.overview, "spacemap.allocated_prefix_format", text) }
        static func spaceMapAllocatedLabel(_ text: String) -> String { L10n.fmt(.overview, "spacemap.allocated_label_format", text) }
        static func spaceMapAssignedLabel(_ text: String) -> String { L10n.fmt(.overview, "spacemap.assigned_label_format", text) }
        static var spaceMapNotMeasured: String { L10n.tr(.overview, "spacemap.not_measured") }
        static func spaceMapLogicalPrefix(_ text: String) -> String { L10n.fmt(.overview, "spacemap.logical_prefix_format", text) }
        static func spaceMapItemsLabel(_ count: Int) -> String { L10n.fmt(.overview, "spacemap.items_label_format", count) }
        static func spaceMapTileItems(_ count: Int) -> String { L10n.fmt(.overview, "spacemap.tiles_items_format", count) }
        static var spaceMapReadOnlyHint: String { L10n.tr(.overview, "spacemap.read_only_hint") }
        static func spaceMapPartialCoverage(_ joined: String) -> String { L10n.fmt(.overview, "spacemap.partial_coverage_format", joined) }
        static var spaceMapEmptyNeedsScan: String { L10n.tr(.overview, "spacemap.empty_needs_scan") }
        static var spaceMapEmptyScope: String { L10n.tr(.overview, "spacemap.empty_scope") }
        static var spaceMapSparseNote: String { L10n.tr(.overview, "spacemap.sparse_note") }
        static var spaceMapInspect: String { L10n.tr(.overview, "spacemap.inspect") }

        static var tasksHeading: String { L10n.tr(.overview, "tasks.heading") }
        static var tasksCleanTitle: String { L10n.tr(.overview, "tasks.clean.title") }
        static var tasksCleanDesc: String { L10n.tr(.overview, "tasks.clean.desc") }
        static func tasksCleanStatusCount(_ count: Int, _ size: String) -> String {
            L10n.fmt(.overview, "tasks.clean.status_count_format", count, size)
        }
        static var tasksExploreTitle: String { L10n.tr(.overview, "tasks.explore.title") }
        static var tasksExploreDesc: String { L10n.tr(.overview, "tasks.explore.desc") }
        static var tasksDuplicatesTitle: String { L10n.tr(.overview, "tasks.duplicates.title") }
        static var tasksDuplicatesDesc: String { L10n.tr(.overview, "tasks.duplicates.desc") }
        static var tasksAppsTitle: String { L10n.tr(.overview, "tasks.apps.title") }
        static var tasksAppsDesc: String { L10n.tr(.overview, "tasks.apps.desc") }
        static var tasksHistoryTitle: String { L10n.tr(.overview, "tasks.history.title") }
        static var tasksHistoryDesc: String { L10n.tr(.overview, "tasks.history.desc") }
        static var tasksAdvancedTitle: String { L10n.tr(.overview, "tasks.advanced.title") }
        static var tasksAdvancedDesc: String { L10n.tr(.overview, "tasks.advanced.desc") }
    }
}

// MARK: - Findings

extension L10n {
    enum Findings {
        static var title: String { L10n.tr(.findings, "title") }
        static var subtitle: String { L10n.tr(.findings, "subtitle") }
        static var showMap: String { L10n.tr(.findings, "show_map") }
        static var hideMap: String { L10n.tr(.findings, "hide_map") }

        static var filterAll: String { L10n.tr(.findings, "filter.all") }
        static var filterReviewable: String { L10n.tr(.findings, "filter.reviewable") }
        static var filterViewOnly: String { L10n.tr(.findings, "filter.view_only") }
        static var modeCandidates: String { L10n.tr(.findings, "mode.candidates") }
        static var modeExplore: String { L10n.tr(.findings, "mode.explore") }
        static var modeDuplicates: String { L10n.tr(.findings, "mode.duplicates") }
        static var modeAdvanced: String { L10n.tr(.findings, "mode.advanced") }
        static var exploreInventoryNotice: String { L10n.tr(.findings, "explore.inventory_notice") }
        static var categoriesAll11: String { L10n.tr(.findings, "categories.all_11") }
        static var categoriesChoose: String { L10n.tr(.findings, "categories.choose") }
        static var searchPlaceholder: String { L10n.tr(.findings, "search.placeholder") }
        static var searchAccessibility: String { L10n.tr(.findings, "search.accessibility") }
        static var filtersLabel: String { L10n.tr(.findings, "filters.label") }
        static var filtersReset: String { L10n.tr(.findings, "filters.reset") }

        static var sortLabel: String { L10n.tr(.findings, "sort.label") }
        static var sortLargest: String { L10n.tr(.findings, "sort.largest") }
        static var sortLogical: String { L10n.tr(.findings, "sort.logical") }
        static var sortNewest: String { L10n.tr(.findings, "sort.newest") }
        static var sortName: String { L10n.tr(.findings, "sort.name") }

        static var filterSize: String { L10n.tr(.findings, "filter.size") }
        static var filterSizeAll: String { L10n.tr(.findings, "filter.size_all") }
        static var filterSizeGt10MB: String { L10n.tr(.findings, "filter.size_gt10mb") }
        static var filterSizeGt100MB: String { L10n.tr(.findings, "filter.size_gt100mb") }
        static var filterSizeGt1GB: String { L10n.tr(.findings, "filter.size_gt1gb") }
        static var filterSizeSparse: String { L10n.tr(.findings, "filter.size_sparse") }

        static var filterType: String { L10n.tr(.findings, "filter.type") }
        static var filterTypeAll: String { L10n.tr(.findings, "filter.type_all") }
        static var filterTypeRegular: String { L10n.tr(.findings, "filter.type_regular") }
        static var filterTypeDirs: String { L10n.tr(.findings, "filter.type_dirs") }

        static var filterStatus: String { L10n.tr(.findings, "filter.status") }
        static var filterStatusAll: String { L10n.tr(.findings, "filter.status_all") }
        static var filterStatusEligible: String { L10n.tr(.findings, "filter.status_eligible") }
        static var filterStatusInventory: String { L10n.tr(.findings, "filter.status_inventory") }
        static var filterStatusInUse: String { L10n.tr(.findings, "filter.status_in_use") }
        static var filterStatusPartial: String { L10n.tr(.findings, "filter.status_partial") }

        static var filterAge: String { L10n.tr(.findings, "filter.age") }
        static var filterAgeAll: String { L10n.tr(.findings, "filter.age_all") }
        static var filterAgeRecent: String { L10n.tr(.findings, "filter.age_recent") }
        static var filterAgeGt7d: String { L10n.tr(.findings, "filter.age_gt7d") }
        static var filterAgeGt30d: String { L10n.tr(.findings, "filter.age_gt30d") }

        static var filterLocation: String { L10n.tr(.findings, "filter.location") }
        static var filterLocationAll: String { L10n.tr(.findings, "filter.location_all") }
        static var filterLocationHidden: String { L10n.tr(.findings, "filter.location_hidden") }
        static var filterLocationRoots: String { L10n.tr(.findings, "filter.location_roots") }

        static var bannerScanning: String { L10n.tr(.findings, "banner.scanning") }
        static func bannerCountAllocated(_ items: String, _ size: String) -> String {
            L10n.fmt(.findings, "banner.count_allocated_format", items, size)
        }
        static var partialIncompleteScan: String { L10n.tr(.findings, "partial.incomplete_scan") }
        static var partialBodyTitle: String { L10n.tr(.findings, "partial.body_title") }
        static var partialBodyDetail: String { L10n.tr(.findings, "partial.body_detail") }
        static var actionSelectReviewable: String { L10n.tr(.findings, "action.select_reviewable") }
        static var actionSelectReviewableHelp: String { L10n.tr(.findings, "action.select_reviewable_help") }
        static var actionClearSelection: String { L10n.tr(.findings, "action.clear_selection") }

        static var emptyLookingTitle: String { L10n.tr(.findings, "empty.looking_title") }
        static var emptyLookingDetail: String { L10n.tr(.findings, "empty.looking_detail") }
        static var emptyScanTitle: String { L10n.tr(.findings, "empty.scan_title") }
        static var emptyScanDetail: String { L10n.tr(.findings, "empty.scan_detail") }
        static var emptyReviewableTitle: String { L10n.tr(.findings, "empty.reviewable_title") }
        static var emptyMatchesTitle: String { L10n.tr(.findings, "empty.matches_title") }
        static var emptyMatchesDetail: String { L10n.tr(.findings, "empty.matches_detail") }

        static var detectorProjectsAndBuilds: String { L10n.tr(.findings, "detector.projects_and_builds") }
        static var detectorConclusionsTitle: String { L10n.tr(.findings, "detector.conclusions_title") }
        static var detectorHeader: String { L10n.tr(.findings, "detector.header") }
        static var detectorInventoryOnlyPill: String { L10n.tr(.findings, "detector.inventory_only_pill") }
        static var detectorExpand: String { L10n.tr(.findings, "detector.expand") }
        static var detectorCollapse: String { L10n.tr(.findings, "detector.collapse") }
        static func detectorShowingUpTo(_ limit: Int) -> String { L10n.fmt(.findings, "detector.showing_up_to_format", limit) }
        static var detectorShowMore25: String { L10n.tr(.findings, "detector.show_more_25") }
        static var detectorRunningOrPending: String { L10n.tr(.findings, "detector.running_or_pending") }
        static var detectorRunScanPrompt: String { L10n.tr(.findings, "detector.run_scan_prompt") }
        static var detectorPartialNote: String { L10n.tr(.findings, "detector.partial_note") }

        static var detectorOrphansTitle: String { L10n.tr(.findings, "detector.orphans.title") }
        static func detectorOrphansCount(_ count: Int) -> String { L10n.fmt(.findings, "detector.orphans.count_format", count) }
        static var detectorOrphansEmpty: String { L10n.tr(.findings, "detector.orphans.empty") }
        static var detectorWorktreesTitle: String { L10n.tr(.findings, "detector.worktrees.title") }
        static func detectorWorktreesCount(_ count: Int) -> String { L10n.fmt(.findings, "detector.worktrees.count_format", count) }
        static var detectorWorktreesEmpty: String { L10n.tr(.findings, "detector.worktrees.empty") }
        static var detectorWorktreesLinked: String { L10n.tr(.findings, "detector.worktrees.linked") }
        static var detectorArtifactsTitle: String { L10n.tr(.findings, "detector.artifacts.title") }
        static func detectorArtifactsCount(_ count: Int) -> String { L10n.fmt(.findings, "detector.artifacts.count_format", count) }
        static var detectorArtifactsEmpty: String { L10n.tr(.findings, "detector.artifacts.empty") }
        static var detectorArtifactsAnchoredIdle: String { L10n.tr(.findings, "detector.artifacts.anchored_idle") }
        static var detectorArtifactsBlocked: String { L10n.tr(.findings, "detector.artifacts.blocked") }

        static var orphanActiveProject: String { L10n.tr(.findings, "orphan.active_project") }
        static var orphanPartial: String { L10n.tr(.findings, "orphan.partial") }
        static var orphanCancelled: String { L10n.tr(.findings, "orphan.cancelled") }
        static var orphanPossiblyOrphaned: String { L10n.tr(.findings, "orphan.possibly_orphaned") }
        static var orphanMissingMetadata: String { L10n.tr(.findings, "orphan.missing_metadata") }
        static var orphanInvalidMetadata: String { L10n.tr(.findings, "orphan.invalid_metadata") }
        static var orphanPermissionDenied: String { L10n.tr(.findings, "orphan.permission_denied") }
        static var orphanUnmountedVolume: String { L10n.tr(.findings, "orphan.unmounted_volume") }

        static var categoryMeasuredSpace: String { L10n.tr(.findings, "category.measured_space") }
        static var categoryPartialNote: String { L10n.tr(.findings, "category.partial_note") }
        static var categoryScanDetails: String { L10n.tr(.findings, "category.scan_details") }
        static func categoryLogicalSize(_ size: String) -> String { L10n.fmt(.findings, "category.logical_size_format", size) }
        static var categorySizeNotMeasured: String { L10n.tr(.findings, "category.size_not_measured") }
        static func categoryVirtualCapacity(_ size: String) -> String { L10n.fmt(.findings, "category.virtual_capacity_format", size) }
        static var categoryEmptyScan: String { L10n.tr(.findings, "category.empty.scan") }
        static var categoryEmptyScanning: String { L10n.tr(.findings, "category.empty.scanning") }
        static var categoryEmptyNoFolders: String { L10n.tr(.findings, "category.empty.no_folders") }
        static var categoryEmptyNoAccess: String { L10n.tr(.findings, "category.empty.no_access") }
        static var categoryEmptyCheckedEmpty: String { L10n.tr(.findings, "category.empty.checked_empty") }
        static var categoryEmptyPartialFiltered: String { L10n.tr(.findings, "category.empty.partial_filtered") }
        static var categoryEmptyFiltered: String { L10n.tr(.findings, "category.empty.filtered") }

        static func categorySummary(for category: StorageCategory) -> String {
            switch category {
            case .vmContainers: return L10n.tr(.findings, "category.summary.vm_containers")
            case .appCaches: return L10n.tr(.findings, "category.summary.app_caches")
            case .packageCaches: return L10n.tr(.findings, "category.summary.package_caches")
            case .developerCaches: return L10n.tr(.findings, "category.summary.dev_caches")
            case .editorExtensions: return L10n.tr(.findings, "category.summary.editor_extensions")
            case .toolchainsAndSDKs: return L10n.tr(.findings, "category.summary.toolchains_sdks")
            case .agentAndEditorHistory: return L10n.tr(.findings, "category.summary.agent_sessions")
            case .temporaryFiles: return L10n.tr(.findings, "category.summary.temp_files")
            case .logsAndCrashes: return L10n.tr(.findings, "category.summary.logs")
            case .appLeftovers: return L10n.tr(.findings, "category.summary.app_leftovers")
            case .downloadsAndInstallers: return L10n.tr(.findings, "category.summary.downloads")
            }
        }

        static func selectionAllocatedSummary(count: Int, size: String) -> String {
            let countStr = L10n.fmt(.findings, count == 1 ? "selection.count_singular" : "selection.count_plural", count)
            return L10n.fmt(.findings, "selection.allocated_summary_format", countStr, size)
        }
        static var selectionHint: String { L10n.tr(.findings, "selection.hint") }
        static var selectionCancelRemaining: String { L10n.tr(.findings, "selection.cancel_remaining") }
        static var selectionReviewButton: String { L10n.tr(.findings, "selection.review_button") }

        static var rowPartialNote: String { L10n.tr(.findings, "row.partial_note") }
        static func rowSparseLogical(_ logical: String) -> String { L10n.fmt(.findings, "row.sparse_logical_format", logical) }
        static var rowAllocatedHelp: String { L10n.tr(.findings, "row.allocated_help") }
        static var rowBadgeReviewable: String { L10n.tr(.findings, "row.badge.reviewable") }
        static var rowBadgeInUse: String { L10n.tr(.findings, "row.badge.in_use") }
        static var rowBadgeProtected: String { L10n.tr(.findings, "row.badge.protected") }
        static var rowBadgePartial: String { L10n.tr(.findings, "row.badge.partial") }
        static var rowBadgeRecent: String { L10n.tr(.findings, "row.badge.recent") }
        static var rowBadgeUnverified: String { L10n.tr(.findings, "row.badge.unverified") }
        static var rowBadgeViewOnly: String { L10n.tr(.findings, "row.badge.view_only") }
        static var rowExplainEligible: String { L10n.tr(.findings, "row.explain.eligible") }
        static func rowExplainRunningApp(_ detail: String) -> String { L10n.fmt(.findings, "row.explain.running_app_format", detail) }
        static var rowExplainInUse: String { L10n.tr(.findings, "row.explain.in_use") }
        static var rowExplainProtected: String { L10n.tr(.findings, "row.explain.protected") }
        static var rowExplainRecent: String { L10n.tr(.findings, "row.explain.recent") }
        static var rowExplainUnverified: String { L10n.tr(.findings, "row.explain.unverified") }
        static var rowExplainDirectory: String { L10n.tr(.findings, "row.explain.directory") }
        static var rowExplainViewOnly: String { L10n.tr(.findings, "row.explain.view_only") }
        static func rowSelectAccessibility(_ title: String) -> String { L10n.fmt(.findings, "row.select_accessibility_format", title) }
        static var rowDetailsOpen: String { L10n.tr(.findings, "row.details_open") }
        static var rowDetailsClosed: String { L10n.tr(.findings, "row.details_closed") }
        static var rowDetailsHelp: String { L10n.tr(.findings, "row.details_help") }
        static func rowLastChange(_ rel: String) -> String { L10n.fmt(.findings, "row.last_change_format", rel) }
        static func rowFilesCounted(_ count: Int) -> String {
            L10n.fmt(.findings, count == 1 ? "row.files_counted_singular" : "row.files_counted_plural", count)
        }
        static var rowViewOnMap: String { L10n.tr(.findings, "row.view_on_map") }
        static var rowTechnicalDetails: String { L10n.tr(.findings, "row.technical_details") }
        static func rowAllocatedSize(_ size: String) -> String { L10n.fmt(.findings, "row.allocated_size_format", size) }
        static func rowLogicalSize(_ size: String) -> String { L10n.fmt(.findings, "row.logical_size_format", size) }
        static func rowSelectableSize(_ size: String) -> String { L10n.fmt(.findings, "row.selectable_size_format", size) }
        static func rowDateBasis(_ basis: String) -> String { L10n.fmt(.findings, "row.date_basis_format", basis) }
        static func rowVirtualCapacity(_ size: String) -> String { L10n.fmt(.findings, "row.virtual_capacity_format", size) }
        static func rowRule(_ rule: String) -> String { L10n.fmt(.findings, "row.rule_format", rule) }
        static func rowDataType(_ tier: String) -> String { L10n.fmt(.findings, "row.data_type_format", tier) }
        static func rowUsageInspection(_ usage: String) -> String { L10n.fmt(.findings, "row.usage_inspection_format", usage) }
        static func rowConfidence(_ confidence: String) -> String { L10n.fmt(.findings, "row.confidence_format", confidence) }
        static var rowGuidanceWhat: String { L10n.tr(.findings, "row.guidance.what") }
        static var rowGuidanceLost: String { L10n.tr(.findings, "row.guidance.lost") }
        static var rowGuidanceRegen: String { L10n.tr(.findings, "row.guidance.regen") }
        static func rowRegenBehavior(_ value: String) -> String { L10n.fmt(.findings, "row.regen_behavior_format", value) }
        static func regenBehaviorLabel(_ behavior: RegenerationBehavior) -> String {
            switch behavior {
            case .rebuilds: return L10n.tr(.findings, "row.regen.rebuilds")
            case .downloads: return L10n.tr(.findings, "row.regen.downloads")
            case .gone: return L10n.tr(.findings, "row.regen.gone")
            case .unknown: return L10n.tr(.findings, "row.regen.unknown")
            }
        }
    }
}

// MARK: - AppsAgents

extension L10n {
    enum AppsAgents {
        static var agentsTitle: String { L10n.tr(.appsAgents, "agents.title") }
        static var agentsSubtitle: String { L10n.tr(.appsAgents, "agents.subtitle") }
        static var agentsExecutionDisabled: String { L10n.tr(.appsAgents, "agents.execution_disabled") }
        static var agentsBody: String { L10n.tr(.appsAgents, "agents.body") }
        static var agentsNotFound: String { L10n.tr(.appsAgents, "agents.not_found") }
        static var agentsStatusLine: String { L10n.tr(.appsAgents, "agents.status_line") }
        static var agentsNotDetected: String { L10n.tr(.appsAgents, "agents.not_detected") }
        static var agentsInstalledReadOnly: String { L10n.tr(.appsAgents, "agents.installed_readonly") }
        static var agentsDetectAgain: String { L10n.tr(.appsAgents, "agents.detect_again") }
        static var agentsMCPTitle: String { L10n.tr(.appsAgents, "agents.mcp_title") }
        static var agentsMCPDescription: String { L10n.tr(.appsAgents, "agents.mcp_description") }

        static var appsTitle: String { L10n.tr(.appsAgents, "apps.title") }
        static var appsSubtitle: String { L10n.tr(.appsAgents, "apps.subtitle") }
        static var appsSearchPlaceholder: String { L10n.tr(.appsAgents, "apps.search_placeholder") }
        static var appsPartialList: String { L10n.tr(.appsAgents, "apps.partial_list") }
        static var appsClosePreview: String { L10n.tr(.appsAgents, "apps.close_preview") }
        static var appsViewOnlyNote: String { L10n.tr(.appsAgents, "apps.view_only_note") }
        static var appsSubtitleUninstaller: String { L10n.tr(.appsAgents, "apps.subtitle_uninstaller") }
        static var appsUninstallNote: String { L10n.tr(.appsAgents, "apps.uninstall_note") }
    }
}

// MARK: - Activity

extension L10n {
    enum Activity {
        static var title: String { L10n.tr(.activity, "title") }
        static var subtitle: String { L10n.tr(.activity, "subtitle") }
        static var cardSelectionTitle: String { L10n.tr(.activity, "card.selection.title") }
        static func cardSelectionDetail(_ count: Int) -> String { L10n.fmt(.activity, "card.selection.detail_format", count) }
        static var cardTrashedTitle: String { L10n.tr(.activity, "card.trashed.title") }
        static func cardTrashedDetail(_ count: Int) -> String { L10n.fmt(.activity, "card.trashed.detail_format", count) }
        static var cardRestoredTitle: String { L10n.tr(.activity, "card.restored.title") }
        static func cardRestoredDetail(_ count: Int) -> String { L10n.fmt(.activity, "card.restored.detail_format", count) }
        static var cardRejectedTitle: String { L10n.tr(.activity, "card.rejected.title") }
        static func cardRejectedDetail(_ count: Int) -> String { L10n.fmt(.activity, "card.rejected.detail_format", count) }
        static var cardDeltaTitle: String { L10n.tr(.activity, "card.delta.title") }
        static var cardDeltaDetail: String { L10n.tr(.activity, "card.delta.detail") }
        static var apfsNote: String { L10n.tr(.activity, "apfs_note") }
        static var sectionLastScan: String { L10n.tr(.activity, "section.last_scan") }
        static var emptyTitle: String { L10n.tr(.activity, "empty.title") }
        static var emptyDetail: String { L10n.tr(.activity, "empty.detail") }
        static func entryLogical(_ size: String) -> String { L10n.fmt(.activity, "entry.logical_format", size) }
        static func entryAllocated(_ size: String) -> String { L10n.fmt(.activity, "entry.allocated_format", size) }
        static func entryDelta(_ size: String) -> String { L10n.fmt(.activity, "entry.delta_format", size) }
        static func entryTrashPath(_ path: String) -> String { L10n.fmt(.activity, "entry.trash_path_format", path) }
        static var entryReviewRestore: String { L10n.tr(.activity, "entry.review_restore") }
        static var sectionScanActivity: String { L10n.tr(.activity, "section.scan_activity") }

        static var onboardingEyebrow: String { L10n.tr(.activity, "onboarding.eyebrow") }
        static var onboardingTitle: String { L10n.tr(.activity, "onboarding.title") }
        static var onboardingSubtitle: String { L10n.tr(.activity, "onboarding.subtitle") }
        static var onboardingCard1Title: String { L10n.tr(.activity, "onboarding.card1.title") }
        static var onboardingCard1Detail: String { L10n.tr(.activity, "onboarding.card1.detail") }
        static var onboardingCard2Title: String { L10n.tr(.activity, "onboarding.card2.title") }
        static var onboardingCard2Detail: String { L10n.tr(.activity, "onboarding.card2.detail") }
        static var onboardingCard3Title: String { L10n.tr(.activity, "onboarding.card3.title") }
        static var onboardingCard3Detail: String { L10n.tr(.activity, "onboarding.card3.detail") }
        static var onboardingCard4Title: String { L10n.tr(.activity, "onboarding.card4.title") }
        static var onboardingCard4Detail: String { L10n.tr(.activity, "onboarding.card4.detail") }
        static var onboardingHint: String { L10n.tr(.activity, "onboarding.hint") }
        static var onboardingStart: String { L10n.tr(.activity, "onboarding.start") }

        static var paletteFindCommand: String { L10n.tr(.activity, "palette.find_command") }
        static var palettePlaceholder: String { L10n.tr(.activity, "palette.placeholder") }
        static var paletteAnalyze: String { L10n.tr(.activity, "palette.analyze") }
        static var paletteAnalyzeStorage: String { L10n.tr(.activity, "palette.analyze_storage") }
        static var paletteHint: String { L10n.tr(.activity, "palette.hint") }

        static var menuCommandPalette: String { L10n.tr(.activity, "menu.command_palette") }
        static var menuAnalyzeStorage: String { L10n.tr(.activity, "menu.analyze_storage") }
        static var quitConfirmActiveTask: String { L10n.tr(.activity, "quit.confirm_active_task") }

        static var logCancelledNoChanges: String { L10n.tr(.activity, "log.cancelled_no_changes") }
        static var logScanStarted: String { L10n.tr(.activity, "log.scan_started") }
        static var logScanCancelledNote: String { L10n.tr(.activity, "log.scan_cancelled_note") }
        static func logScanFinished(items: Int, measured: Int, total: Int, complete: Bool) -> String {
            let status = L10n.tr(.activity, complete ? "scan.complete" : "scan.partial")
            return L10n.fmt(.activity, "log.scan_finished_format", items, measured, total, status)
        }
        static func logTrashFinished(moved: Int, total: Int) -> String {
            L10n.fmt(.activity, "log.trash_finished_format", moved, total)
        }
        static var notificationTrashTitle: String { L10n.tr(.activity, "notification.trash_title") }
        static func notificationTrashBody(moved: Int, total: Int) -> String {
            L10n.fmt(.activity, "notification.trash_body_format", moved, total)
        }
        static var logRestoredFromTrash: String { L10n.tr(.activity, "log.restored_from_trash") }
        static var logConclusionsDataOnly: String { L10n.tr(.activity, "log.conclusions_data_only") }

        static var alertTrashTitle: String { L10n.tr(.activity, "alert.trash.title") }
        static var alertTrashDetail: String { L10n.tr(.activity, "alert.trash.detail") }
        static func alertTrashItem(allocated: String, logical: String, path: String) -> String {
            L10n.fmt(.activity, "alert.trash.item_format", allocated, logical, path)
        }
        static var alertTrashButton: String { L10n.tr(.activity, "alert.trash.button") }
        static var alertRestoreTitle: String { L10n.tr(.activity, "alert.restore.title") }
        static var alertRestoreDetail: String { L10n.tr(.activity, "alert.restore.detail") }
        static var alertRestoreButton: String { L10n.tr(.activity, "alert.restore.button") }
        static var alertRemoveProtectionTitle: String { L10n.tr(.activity, "alert.remove_protection.title") }
        static var alertRemoveProtectionDetail: String { L10n.tr(.activity, "alert.remove_protection.detail") }
        static var cardOutcomesTitle: String { L10n.tr(.activity, "card.outcomes.title") }
        static func cardOutcomesDetail(_ planned: Int, _ completed: Int, _ partialOrFailed: Int) -> String {
            L10n.fmt(.activity, "card.outcomes.detail_format", planned, completed, partialOrFailed)
        }
        static func entryMechanism(_ mechanism: String) -> String {
            let label: String
            switch mechanism {
            case "trash": label = L10n.tr(.activity, "mechanism.trash")
            case "tool_command", "tool": label = L10n.tr(.activity, "mechanism.tool_command")
            case "mixed": label = L10n.tr(.activity, "mechanism.mixed")
            default: label = mechanism
            }
            return L10n.fmt(.activity, "entry.mechanism_format", label)
        }
        static var entryRestorableYes: String { L10n.tr(.activity, "entry.restorable_yes") }
        static var entryRestorableNo: String { L10n.tr(.activity, "entry.restorable_no") }
        static func entryDomain(_ domain: String) -> String {
            let label: String
            switch domain {
            case "cache_inventory": label = L10n.tr(.activity, "domain.cache_inventory")
            case "project_artifacts": label = L10n.tr(.activity, "domain.project_artifacts")
            case "package_managers": label = L10n.tr(.activity, "domain.package_managers")
            case "exact_duplicates": label = L10n.tr(.activity, "domain.exact_duplicates")
            case "app_uninstall", "app_uninstaller": label = L10n.tr(.activity, "domain.app_uninstall")
            case "docker": label = L10n.tr(.activity, "domain.docker")
            default: label = domain
            }
            return L10n.fmt(.activity, "entry.domain_format", label)
        }
        static func entryCounts(_ completed: Int, _ skippedOrFailed: Int) -> String {
            L10n.fmt(.activity, "entry.counts_format", completed, skippedOrFailed)
        }
    }
}

// MARK: - Settings

extension L10n {
    enum Settings {
        static var eyebrow: String { L10n.tr(.settings, "eyebrow") }
        static var title: String { L10n.tr(.settings, "title") }
        static var subtitle: String { L10n.tr(.settings, "subtitle") }

        static var languageTitle: String { L10n.tr(.settings, "language.title") }
        static var languageSystem: String { L10n.tr(.settings, "language.system") }
        static var languageES: String { L10n.tr(.settings, "language.es") }
        static var languageEN: String { L10n.tr(.settings, "language.en") }
        static var languageHint: String { L10n.tr(.settings, "language.hint") }

        static func label(for language: AppLanguage) -> String {
            switch language {
            case .system: return languageSystem
            case .es: return languageES
            case .en: return languageEN
            }
        }

        static var appearanceTitle: String { L10n.tr(.settings, "appearance.title") }

        static var inventoryRootsTitle: String { L10n.tr(.settings, "inventory_roots.title") }
        static var inventoryRootsPill: String { L10n.tr(.settings, "inventory_roots.pill") }
        static var inventoryRootsDescription: String { L10n.tr(.settings, "inventory_roots.description") }
        static func inventoryRootsRemoveAccessibility(_ path: String) -> String {
            L10n.fmt(.settings, "inventory_roots.remove_accessibility_format", path)
        }
        static var inventoryRootsAddButton: String { L10n.tr(.settings, "inventory_roots.add_button") }
        static var inventoryRootsPanelMessage: String { L10n.tr(.settings, "inventory_roots.panel_message") }

        static var cleanupRootsTitle: String { L10n.tr(.settings, "cleanup_roots.title") }
        static var cleanupRootsPill: String { L10n.tr(.settings, "cleanup_roots.pill") }
        static var cleanupRootsDescription: String { L10n.tr(.settings, "cleanup_roots.description") }
        static func cleanupRootsRemoveAccessibility(_ path: String) -> String {
            L10n.fmt(.settings, "cleanup_roots.remove_accessibility_format", path)
        }
        static var cleanupRootsAddButton: String { L10n.tr(.settings, "cleanup_roots.add_button") }
        static var cleanupRootsPanelMessage: String { L10n.tr(.settings, "cleanup_roots.panel_message") }

        static var exclusionsTitle: String { L10n.tr(.settings, "exclusions.title") }
        static var exclusionsRemoveButton: String { L10n.tr(.settings, "exclusions.remove_button") }
        static var exclusionsEmpty: String { L10n.tr(.settings, "exclusions.empty") }
        static var exclusionsAddButton: String { L10n.tr(.settings, "exclusions.add_button") }
        static var exclusionsAlwaysProtected: String { L10n.tr(.settings, "exclusions.always_protected") }

        static var privacyTitle: String { L10n.tr(.settings, "privacy.title") }
        static var privacyDescription: String { L10n.tr(.settings, "privacy.description") }
        static var privacyOpenSystemSettings: String { L10n.tr(.settings, "privacy.open_system_settings") }

        static var notificationsTitle: String { L10n.tr(.settings, "notifications.title") }
        static var notificationsEnabled: String { L10n.tr(.settings, "notifications.enabled") }
        static var notificationsDisabled: String { L10n.tr(.settings, "notifications.disabled") }
        static var notificationsDisableButton: String { L10n.tr(.settings, "notifications.disable_button") }
        static var notificationsEnableButton: String { L10n.tr(.settings, "notifications.enable_button") }
        static var notificationsNotRequested: String { L10n.tr(.settings, "notifications.not_requested") }
        static var notificationsAuthorized: String { L10n.tr(.settings, "notifications.authorized") }
        static var notificationsNotAuthorized: String { L10n.tr(.settings, "notifications.not_authorized") }

        static var pathStateExplicitlyAuthorized: String { L10n.tr(.settings, "path_state.explicitly_authorized") }
        static var pathStateAccessible: String { L10n.tr(.settings, "path_state.accessible") }
        static var pathStateDenied: String { L10n.tr(.settings, "path_state.denied") }
        static var pathStateRequiresAuthorization: String { L10n.tr(.settings, "path_state.requires_authorization") }
        static var pathStateSensitiveBlocked: String { L10n.tr(.settings, "path_state.sensitive_blocked") }
        static var pathStateMissing: String { L10n.tr(.settings, "path_state.missing") }
        static var pathStateNotVerified: String { L10n.tr(.settings, "path_state.not_verified") }

        static var menuBarFreeSpaceTitle: String { L10n.tr(.settings, "menu_bar_free_space.title") }
        static var menuBarFreeSpaceHint: String { L10n.tr(.settings, "menu_bar_free_space.hint") }
        static var advancedTitle: String { L10n.tr(.settings, "advanced.title") }
        static var advancedSubtitle: String { L10n.tr(.settings, "advanced.subtitle") }
    }
}
