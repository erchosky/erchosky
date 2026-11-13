import Foundation
import BrisaCore

extension L10n {
    enum Tools {
        static var title: String { L10n.tr(.tools, "title") }
        static var subtitle: String { L10n.tr(.tools, "subtitle") }
        static var tabProjects: String { L10n.tr(.tools, "tab.projects") }
        static var tabPackages: String { L10n.tr(.tools, "tab.packages") }
        static var tabDuplicates: String { L10n.tr(.tools, "tab.duplicates") }
        static var tabDocker: String { L10n.tr(.tools, "tab.docker") }

        static var scan: String { L10n.tr(.tools, "common.scan") }
        static var rescan: String { L10n.tr(.tools, "common.rescan") }
        static var recheck: String { L10n.tr(.tools, "common.recheck") }
        static var cancel: String { L10n.tr(.tools, "common.cancel") }
        static var back: String { L10n.tr(.tools, "common.back") }
        static var close: String { L10n.tr(.tools, "common.close") }
        static var reviewPlan: String { L10n.tr(.tools, "common.review_plan") }
        static var executePlan: String { L10n.tr(.tools, "common.execute_plan") }
        static var confirmTrash: String { L10n.tr(.tools, "common.confirm_trash") }
        static var confirmTool: String { L10n.tr(.tools, "common.confirm_tool") }
        static func selectedCount(_ count: Int, _ size: String) -> String {
            L10n.fmt(.tools, "common.selected_count_format", count, size)
        }
        static func modified(_ date: String) -> String {
            L10n.fmt(.tools, "common.modified_format", date)
        }
        static func allocatedLogical(_ allocated: String, _ logical: String) -> String {
            L10n.fmt(.tools, "common.allocated_logical_format", allocated, logical)
        }
        static var showInFinder: String { L10n.tr(.tools, "common.show_in_finder") }
        static var locked: String { L10n.tr(.tools, "common.locked") }
        static var selectAllEligible: String { L10n.tr(.tools, "common.select_all_eligible") }
        static var clearSelection: String { L10n.tr(.tools, "common.clear_selection") }
        static var working: String { L10n.tr(.tools, "common.working") }

        static var planHeader: String { L10n.tr(.tools, "plan.header") }
        static func planAffects(_ count: Int) -> String {
            L10n.fmt(.tools, "plan.affects_format", count)
        }
        static var planPreserved: String { L10n.tr(.tools, "plan.preserved") }
        static var planSizeMeasured: String { L10n.tr(.tools, "plan.size_measured") }
        static var planSizeEstimated: String { L10n.tr(.tools, "plan.size_estimated") }
        static var planSizeMixed: String { L10n.tr(.tools, "plan.size_mixed") }
        static var planRegeneration: String { L10n.tr(.tools, "plan.regeneration") }
        static var planMechanismTrash: String { L10n.tr(.tools, "plan.mechanism.trash") }
        static var planMechanismTool: String { L10n.tr(.tools, "plan.mechanism.tool") }
        static var planMechanismMixed: String { L10n.tr(.tools, "plan.mechanism.mixed") }
        static var planRestorableYes: String { L10n.tr(.tools, "plan.restorable.yes") }
        static var planRestorablePartial: String { L10n.tr(.tools, "plan.restorable.partial") }
        static var planRestorableNo: String { L10n.tr(.tools, "plan.restorable.no") }
        static var planBlockers: String { L10n.tr(.tools, "plan.blockers") }
        static var planVolumeUnlock: String { L10n.tr(.tools, "plan.volume_unlock") }
        static var planBlockedBanner: String { L10n.tr(.tools, "plan.blocked_banner") }

        static var projectsTitle: String { L10n.tr(.tools, "projects.title") }
        static var projectsSubtitle: String { L10n.tr(.tools, "projects.subtitle") }
        static var projectsAddRoot: String { L10n.tr(.tools, "projects.add_root") }
        static var projectsEmpty: String { L10n.tr(.tools, "projects.empty") }
        static func projectsTechnology(_ tech: String) -> String {
            L10n.fmt(.tools, "projects.technology_format", tech)
        }
        static var projectsRebuildLabel: String { L10n.tr(.tools, "projects.rebuild_label") }
        static var projectsUncertaintyNote: String { L10n.tr(.tools, "projects.uncertainty_note") }

        static var packagesTitle: String { L10n.tr(.tools, "packages.title") }
        static var packagesSubtitle: String { L10n.tr(.tools, "packages.subtitle") }
        static var packagesEmpty: String { L10n.tr(.tools, "packages.empty") }
        static var packagesNotInstalled: String { L10n.tr(.tools, "packages.not_installed") }
        static func packagesVersion(_ version: String) -> String {
            L10n.fmt(.tools, "packages.version_format", version)
        }
        static func packagesCachePath(_ path: String) -> String {
            L10n.fmt(.tools, "packages.cache_path_format", path)
        }
        static var packagesScopeWhole: String { L10n.tr(.tools, "packages.scope.whole") }
        static var packagesScopePartial: String { L10n.tr(.tools, "packages.scope.partial") }
        static var packagesWholeWarning: String { L10n.tr(.tools, "packages.whole_warning") }

        static var duplicatesTitle: String { L10n.tr(.tools, "duplicates.title") }
        static var duplicatesSubtitle: String { L10n.tr(.tools, "duplicates.subtitle") }
        static var duplicatesChooseFolder: String { L10n.tr(.tools, "duplicates.choose_folder") }
        static func duplicatesAuthorizedRoots(_ count: Int) -> String {
            L10n.fmt(.tools, "duplicates.authorized_roots_format", count)
        }
        static var duplicatesEmpty: String { L10n.tr(.tools, "duplicates.empty") }
        static func duplicatesProgress(_ examined: Int, _ candidates: Int, _ groups: Int) -> String {
            L10n.fmt(.tools, "duplicates.progress_format", examined, candidates, groups)
        }
        static func duplicatesGroups(_ count: Int) -> String {
            L10n.fmt(.tools, "duplicates.groups_format", count)
        }
        static func duplicatesReclaimableVsSelected(_ selected: String, _ reclaimable: String) -> String {
            L10n.fmt(.tools, "duplicates.reclaimable_vs_selected_format", selected, reclaimable)
        }
        static var duplicatesAPFSCloneNote: String { L10n.tr(.tools, "duplicates.apfs_clone_note") }
        static var duplicatesProtectedCopy: String { L10n.tr(.tools, "duplicates.protected_copy") }
        static var duplicatesSurplusCopy: String { L10n.tr(.tools, "duplicates.surplus_copy") }

        static var dockerTitle: String { L10n.tr(.tools, "docker.title") }
        static var dockerSubtitle: String { L10n.tr(.tools, "docker.subtitle") }
        static var dockerSectionContainers: String { L10n.tr(.tools, "docker.section.containers") }
        static var dockerSectionImages: String { L10n.tr(.tools, "docker.section.images") }
        static var dockerSectionBuildCache: String { L10n.tr(.tools, "docker.section.buildcache") }
        static var dockerSectionVolumes: String { L10n.tr(.tools, "docker.section.volumes") }
        static var dockerUnlockVolume: String { L10n.tr(.tools, "docker.unlock_volume") }
        static var dockerVolumeLocked: String { L10n.tr(.tools, "docker.volume_locked") }
        static var dockerRunningProtected: String { L10n.tr(.tools, "docker.running_protected") }
        static var dockerBuildCacheReclaimable: String { L10n.tr(.tools, "docker.buildcache_reclaimable") }
        static var dockerBuildCacheAll: String { L10n.tr(.tools, "docker.buildcache_all") }
        static func dockerSharedUnique(_ virtual: String, _ shared: String, _ unique: String) -> String {
            L10n.fmt(.tools, "docker.shared_unique_format", virtual, shared, unique)
        }
        static func dockerUsedBy(_ names: String) -> String {
            L10n.fmt(.tools, "docker.used_by_format", names)
        }
        static var dockerEmpty: String { L10n.tr(.tools, "docker.empty") }

        static var uninstallerInspect: String { L10n.tr(.tools, "uninstaller.inspect") }
        static var uninstallerExclusive: String { L10n.tr(.tools, "uninstaller.exclusive") }
        static var uninstallerShared: String { L10n.tr(.tools, "uninstaller.shared") }
        static var uninstallerUncertain: String { L10n.tr(.tools, "uninstaller.uncertain") }
        static var uninstallerPrivileged: String { L10n.tr(.tools, "uninstaller.privileged") }
        static var uninstallerRunningBlocker: String { L10n.tr(.tools, "uninstaller.running_blocker") }
        static var uninstallerQuitApp: String { L10n.tr(.tools, "uninstaller.quit_app") }
        static var uninstallerPlanAction: String { L10n.tr(.tools, "uninstaller.plan_action") }
        static var uninstallerSystemProtected: String { L10n.tr(.tools, "uninstaller.system_protected") }
        static var uninstallerIncludeAppBundle: String { L10n.tr(.tools, "uninstaller.include_app_bundle") }
        static func uninstallerConfidence(_ level: AppMatchConfidence) -> String {
            switch level {
            case .highBundleID: return L10n.tr(.tools, "uninstaller.confidence.high")
            case .mediumTeamOrGroup: return L10n.tr(.tools, "uninstaller.confidence.medium")
            case .lowNameOnly: return L10n.tr(.tools, "uninstaller.confidence.low")
            }
        }
        static func uninstallerSharedWith(_ apps: String) -> String {
            L10n.fmt(.tools, "uninstaller.shared_with_format", apps)
        }

        static var technicalDetails: String { L10n.tr(.tools, "common.technical_details") }
        static var planSummaryWhat: String { L10n.tr(.tools, "plan.summary.what") }
        static var planSummarySize: String { L10n.tr(.tools, "plan.summary.size") }
        static var planSummaryRecovery: String { L10n.tr(.tools, "plan.summary.recovery") }
        static var planTechnicalSection: String { L10n.tr(.tools, "plan.technical_section") }
        static var planCommandPreview: String { L10n.tr(.tools, "plan.command_preview") }
        static var resultMovedTrashTitle: String { L10n.tr(.tools, "result.moved_trash_title") }
        static var resultCompletedTitle: String { L10n.tr(.tools, "result.completed_title") }
        static var resultFreeDeltaTitle: String { L10n.tr(.tools, "result.free_delta_title") }
        static var resultFreeDeltaTrashNote: String { L10n.tr(.tools, "result.free_delta_trash_note") }
        static var dockerBuildCacheReclaimablePlain: String { L10n.tr(.tools, "docker.buildcache_reclaimable_plain") }
        static var dockerBuildCacheAllPlain: String { L10n.tr(.tools, "docker.buildcache_all_plain") }
    }
}
