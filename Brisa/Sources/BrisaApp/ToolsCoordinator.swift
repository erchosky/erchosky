import SwiftUI
import AppKit
import BrisaCore

enum MenuPanelRoute: Hashable {
    case home
    case reviewCandidates
    case exploreSpace
    case toolsHub
    case category(StorageCategory)
    case toolProjects
    case toolPackages
    case toolDuplicates
    case toolApps
    case toolDocker
    case reviewPlan
    case executionResult
}

enum MainToolsTab: String, CaseIterable, Identifiable {
    case projects
    case packages
    case duplicates
    case docker

    var id: String { rawValue }
}

enum TriStateCheckmark: Equatable {
    case unchecked
    case mixed
    case checked
}

enum PendingOperationPayload {
    case inventoryFiles(ids: [String])
    case projectArtifacts(targets: [ProjectArtifactAuditEntry], policy: ProjectArtifactCleanupPolicy, cleaner: ProjectArtifactCleaner)
    case packageManager(inspection: PackageManagerInspection, capability: PackageManagerOperationCapability, service: PackageManagerService)
    case exactDuplicates(selections: [DuplicateGroupSelection], scope: DuplicateScopePolicy)
    case appUninstall(inspection: AppUninstallInspection)
    case docker(selection: DockerCleanupSelection, manager: DockerManager)
}

struct PendingPlanContext: Identifiable {
    var id: String { plan.id }
    let plan: OperationPlan
    let payload: PendingOperationPayload
    let fromMenuBar: Bool

    var technicalCommandsPreview: [String] {
        switch payload {
        case let .packageManager(_, capability, _):
            return [capability.commandPreview]
        case let .docker(selection, _):
            var cmds: [String] = []
            if !selection.containerIDs.isEmpty {
                cmds.append("docker rm \(selection.containerIDs.joined(separator: " "))")
            }
            if !selection.imageIDs.isEmpty {
                cmds.append("docker image rm \(selection.imageIDs.joined(separator: " "))")
            }
            if let scope = selection.buildCacheScope {
                cmds.append(scope == .all ? "docker builder prune --all --force" : "docker builder prune --force")
            }
            if !selection.volumeNames.isEmpty {
                cmds.append("docker volume rm \(selection.volumeNames.joined(separator: " "))")
            }
            return cmds
        default:
            return []
        }
    }
}

@MainActor
final class ToolsCoordinator: ObservableObject {
    // MARK: - Navigation & Persistent Popover UI State

    @Published var activeToolsTab: MainToolsTab = .projects
    @Published var menuRoute: MenuPanelRoute = .home
    @Published var menuRouteStack: [MenuPanelRoute] = []
    @Published var expandedMenuCategories: Set<StorageCategory> = []
    @Published var expandedProjectGroupIDs: Set<String> = []
    @Published var expandedDuplicateGroupIDs: Set<String> = []
    @Published var showMenuPlanSheetInWindow = false

    // MARK: - Project Artifacts

    @Published var projectAuthorizedRoots: [String] = []
    @Published var projectGroups: [ProjectArtifactGroup] = []
    @Published var selectedProjectArtifactIDs: Set<String> = []
    @Published var isScanningProjects = false
    @Published var projectsError: String?

    // MARK: - Package Managers

    @Published var packageInspections: [PackageManagerInspection] = []
    @Published var selectedCapabilityByManager: [PackageManagerKind: String] = [:]
    @Published var isScanningPackages = false
    @Published var packagesError: String?

    // MARK: - Exact Duplicates (own authorization scope)

    @Published var duplicateAuthorizedRoots: [String] = []
    @Published var duplicateReport: DuplicateScanReport?
    @Published var duplicateProgress: DuplicateScanProgress?
    @Published var duplicateKeptCopyByGroup: [String: String] = [:]
    @Published var duplicateSelectedDeletePaths: Set<String> = []
    @Published var isScanningDuplicates = false
    @Published private var duplicatesErrorPair: (es: String, en: String)?
    @Published private var duplicatesRawError: String?
    var duplicatesError: String? {
        get {
            if let pair = duplicatesErrorPair {
                return L10n.bilingual(es: pair.es, en: pair.en)
            }
            return duplicatesRawError
        }
        set {
            duplicatesErrorPair = nil
            duplicatesRawError = newValue
        }
    }

    // MARK: - Application Uninstaller

    @Published var selectedAppID: String?
    @Published var inspectedApp: AppUninstallInspection?
    @Published var selectedUninstallItemIDs: Set<String> = []
    @Published var includeAppBundleInUninstall = true
    @Published var isInspectingApp = false
    @Published var appUninstallError: String?

    // MARK: - Docker

    @Published var dockerSnapshot: DockerInspectionSnapshot?
    @Published var selectedDockerContainerIDs: Set<String> = []
    @Published var selectedDockerImageIDs: Set<String> = []
    @Published var selectedDockerVolumeNames: Set<String> = []
    @Published var unlockedDockerVolumeNames: Set<String> = []
    @Published var selectedDockerBuildCacheScope: DockerBuildCachePruneScope?
    @Published var isInspectingDocker = false
    @Published var dockerError: String?

    // MARK: - Plan Review & Execution

    @Published var pendingPlanContext: PendingPlanContext?
    @Published var lastExecutionReport: OperationExecutionReport?
    @Published var isExecutingPlan = false
    @Published var isRecheckingPlan = false
    @Published var dockerVolumeConfirmationChecked = false

    // MARK: - Dependencies & Cancellation

    private let homeProvider: () -> String
    private let protectedPathsProvider: () -> [String]
    private let readPolicyProvider: () -> ReadAuthorizationPolicy
    private let inventoryRootsProvider: () -> [String]
    private let allInstalledAppPathsProvider: () -> [String]
    private let journalProvider: () -> Journal?
    private let trashInventoryExecutor: ([String]) async -> OperationExecutionReport?
    private let onJournalUpdated: () -> Void
    private let executor: any CommandExecuting
    private let trashMover: any TrashMoving
    private var securityScopedDuplicateURLs: [String: URL] = [:]
    private var securityScopedProjectURLs: [String: URL] = [:]

    private var projectsCancellation: CancellationFlag?
    private var packagesCancellation: CancellationFlag?
    private var duplicatesCancellation: CancellationFlag?
    private var appInspectCancellation: CancellationFlag?
    private var dockerCancellation: CancellationFlag?
    private var recheckCancellation: CancellationFlag?
    private var executionCancellation: CancellationFlag?

    private var projectsGeneration: UInt64 = 0
    private var packagesGeneration: UInt64 = 0
    private var duplicatesGeneration: UInt64 = 0
    private var appInspectionGeneration: UInt64 = 0
    private var dockerGeneration: UInt64 = 0
    private var recheckGeneration: UInt64 = 0

    private var cachedUninstallerConfigKey: String?
    private var cachedUninstaller: AppUninstaller?

    init(
        homeProvider: @escaping () -> String,
        protectedPathsProvider: @escaping () -> [String],
        readPolicyProvider: @escaping () -> ReadAuthorizationPolicy,
        inventoryRootsProvider: @escaping () -> [String],
        allInstalledAppPathsProvider: @escaping () -> [String],
        journalProvider: @escaping () -> Journal?,
        trashInventoryExecutor: @escaping ([String]) async -> OperationExecutionReport?,
        onJournalUpdated: @escaping () -> Void,
        executor: any CommandExecuting = LiveCommandExecutor(),
        trashMover: any TrashMoving = SystemTrashMover()
    ) {
        self.homeProvider = homeProvider
        self.protectedPathsProvider = protectedPathsProvider
        self.readPolicyProvider = readPolicyProvider
        self.inventoryRootsProvider = inventoryRootsProvider
        self.allInstalledAppPathsProvider = allInstalledAppPathsProvider
        self.journalProvider = journalProvider
        self.trashInventoryExecutor = trashInventoryExecutor
        self.onJournalUpdated = onJournalUpdated
        self.executor = executor
        self.trashMover = trashMover
    }

    // MARK: - Menu-Bar-First Navigation

    func pushMenuRoute(_ next: MenuPanelRoute) {
        guard menuRoute != next else { return }
        menuRouteStack.append(menuRoute)
        menuRoute = next
    }

    var hasActiveWork: Bool {
        isScanningProjects
        || isScanningPackages
        || isScanningDuplicates
        || isInspectingApp
        || isInspectingDocker
        || isExecutingPlan
        || isRecheckingPlan
    }

    func popMenuRoute() {
        let leaving = menuRoute
        if leaving == .reviewPlan && isExecutingPlan {
            return
        }
        if let previous = menuRouteStack.popLast() {
            menuRoute = previous
        } else {
            menuRoute = .home
        }
        cleanupRouteExit(leaving)
    }

    func resetMenuToHome() {
        let leaving = menuRoute
        menuRouteStack.removeAll()
        menuRoute = .home
        cleanupRouteExit(leaving)
    }

    private func cleanupRouteExit(_ route: MenuPanelRoute) {
        if route == .reviewPlan && !isExecutingPlan {
            recheckCancellation?.cancel()
            recheckCancellation = nil
            recheckGeneration &+= 1
            isRecheckingPlan = false
            pendingPlanContext = nil
        } else if route == .executionResult {
            pendingPlanContext = nil
            lastExecutionReport = nil
        }
    }

    func toggleExpandedMenuCategory(_ category: StorageCategory) {
        if expandedMenuCategories.contains(category) {
            expandedMenuCategories.remove(category)
        } else {
            expandedMenuCategories.insert(category)
        }
    }

    func cancelActiveWork() {
        projectsCancellation?.cancel()
        packagesCancellation?.cancel()
        duplicatesCancellation?.cancel()
        appInspectCancellation?.cancel()
        dockerCancellation?.cancel()
        recheckCancellation?.cancel()
        executionCancellation?.cancel()
    }

    func cancelAllActiveWork() {
        cancelActiveWork()
        projectsGeneration &+= 1
        packagesGeneration &+= 1
        duplicatesGeneration &+= 1
        appInspectionGeneration &+= 1
        dockerGeneration &+= 1
        recheckGeneration &+= 1

        projectsCancellation = nil
        packagesCancellation = nil
        duplicatesCancellation = nil
        appInspectCancellation = nil
        dockerCancellation = nil
        recheckCancellation = nil

        isScanningProjects = false
        isScanningPackages = false
        isScanningDuplicates = false
        isInspectingApp = false
        isInspectingDocker = false
        isRecheckingPlan = false
    }

    // MARK: - Project Artifacts

    var effectiveProjectRoots: [String] {
        var combined = inventoryRootsProvider()
        for path in projectAuthorizedRoots where !combined.contains(path) {
            combined.append(path)
        }
        return combined
    }

    func projectPolicy() -> ProjectArtifactCleanupPolicy {
        let basePolicy = readPolicyProvider()
        let authRoots = Array(Set(basePolicy.authorizedPromptRoots + projectAuthorizedRoots))
        let updatedPolicy = ReadAuthorizationPolicy(
            home: homeProvider(),
            projectRoots: effectiveProjectRoots,
            protectedPaths: protectedPathsProvider(),
            allowSystemLocations: true,
            authorizedPromptRoots: authRoots
        )
        return ProjectArtifactCleanupPolicy(
            home: homeProvider(),
            readPolicy: updatedPolicy,
            protectedPaths: protectedPathsProvider(),
            checkActiveProcesses: true
        )
    }

    func chooseProjectRootFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: homeProvider(), isDirectory: true)
        panel.message = L10n.Tools.projectsAddRoot
        if panel.runModal() == .OK, let url = panel.url {
            addProjectRoot(url: url)
        }
    }

    func addProjectRoot(url: URL) {
        let norm = Paths.normalized(url.path)
        guard !norm.isEmpty else { return }
        _ = url.startAccessingSecurityScopedResource()
        securityScopedProjectURLs[norm]?.stopAccessingSecurityScopedResource()
        securityScopedProjectURLs[norm] = url
        if !projectAuthorizedRoots.contains(norm) {
            projectAuthorizedRoots.append(norm)
        }
    }

    func removeProjectRoot(_ path: String) {
        projectAuthorizedRoots.removeAll { $0 == path }
        securityScopedProjectURLs.removeValue(forKey: path)?.stopAccessingSecurityScopedResource()
    }

    func scanProjects() {
        guard !isScanningProjects else { return }
        isScanningProjects = true
        projectsError = nil
        let roots = effectiveProjectRoots
        let policy = projectPolicy()
        projectsCancellation?.cancel()
        let flag = CancellationFlag()
        projectsCancellation = flag
        projectsGeneration &+= 1
        let gen = projectsGeneration

        guard let journal = resolvedJournal() else {
            isScanningProjects = false
            projectsError = "Journal unavailable"
            return
        }

        let cleaner = ProjectArtifactCleaner(journal: journal, policy: policy, mover: trashMover)
        Task { @MainActor [weak self] in
            let groups = await Task.detached(priority: .utility) {
                let control = ScanControl(cancellation: flag, deadline: Date().addingTimeInterval(35))
                return cleaner.scanGroups(authorizedRoots: roots, control: control)
            }.value
            guard let self, self.projectsGeneration == gen, !flag.isCancelled else {
                if let self, self.projectsGeneration == gen {
                    self.isScanningProjects = false
                }
                return
            }
            self.projectGroups = groups
            let validIDs = Set(groups.flatMap(\.artifacts).filter { policy.evaluate($0).allowed }.map(\.id))
            self.selectedProjectArtifactIDs = self.selectedProjectArtifactIDs.intersection(validIDs)
            if let first = groups.first, self.expandedProjectGroupIDs.isEmpty {
                self.expandedProjectGroupIDs.insert(first.id)
            }
            self.isScanningProjects = false
        }
    }

    func toggleProjectArtifact(_ entry: ProjectArtifactAuditEntry, decision: ProjectArtifactCleanupDecision) {
        guard decision.allowed else { return }
        if selectedProjectArtifactIDs.contains(entry.id) {
            selectedProjectArtifactIDs.remove(entry.id)
        } else {
            selectedProjectArtifactIDs.insert(entry.id)
        }
    }

    func selectAllEligibleProjectArtifacts() {
        let policy = projectPolicy()
        let eligible = projectGroups.flatMap(\.artifacts).filter { policy.evaluate($0).allowed }.map(\.id)
        selectedProjectArtifactIDs = Set(eligible)
    }

    func selectedProjectArtifactsSizeBytes() -> Int64 {
        let all = projectGroups.flatMap(\.artifacts)
        return all.filter { selectedProjectArtifactIDs.contains($0.id) }.reduce(Int64(0)) { $0 + $1.allocatedBytes }
    }

    func prepareProjectCleanupPlan(fromMenuBar: Bool) {
        let policy = projectPolicy()
        guard let journal = resolvedJournal() else { return }
        let cleaner = ProjectArtifactCleaner(journal: journal, policy: policy, mover: trashMover)
        let targets = projectGroups.flatMap(\.artifacts).filter { selectedProjectArtifactIDs.contains($0.id) }
        let plan = policy.buildPlan(selectedArtifacts: targets)
        presentPlan(
            PendingPlanContext(
                plan: plan,
                payload: .projectArtifacts(targets: targets, policy: policy, cleaner: cleaner),
                fromMenuBar: fromMenuBar
            )
        )
    }

    // MARK: - Package Managers

    func scanPackageManagers() {
        guard !isScanningPackages else { return }
        isScanningPackages = true
        packagesError = nil
        let home = homeProvider()
        let policy = readPolicyProvider()
        packagesCancellation?.cancel()
        let flag = CancellationFlag()
        packagesCancellation = flag
        packagesGeneration &+= 1
        let gen = packagesGeneration

        guard let journal = resolvedJournal() else {
            isScanningPackages = false
            packagesError = "Journal unavailable"
            return
        }

        let service = PackageManagerService(
            journal: journal,
            home: home,
            readPolicy: policy,
            executor: executor
        )
        Task { @MainActor [weak self] in
            let inspections = await Task.detached(priority: .utility) {
                let control = ScanControl(cancellation: flag, deadline: Date().addingTimeInterval(35))
                return service.inspectAll(control: control)
            }.value
            guard let self, self.packagesGeneration == gen, !flag.isCancelled else {
                if let self, self.packagesGeneration == gen {
                    self.isScanningPackages = false
                }
                return
            }
            self.packageInspections = inspections
            for insp in inspections where self.selectedCapabilityByManager[insp.kind] == nil {
                if let first = insp.capabilities.first(where: \.isAvailable) ?? insp.capabilities.first {
                    self.selectedCapabilityByManager[insp.kind] = first.id
                }
            }
            self.isScanningPackages = false
        }
    }

    func preparePackageManagerPlan(
        inspection: PackageManagerInspection,
        capability: PackageManagerOperationCapability,
        fromMenuBar: Bool
    ) {
        guard let journal = resolvedJournal() else { return }
        let service = PackageManagerService(
            journal: journal,
            home: homeProvider(),
            readPolicy: readPolicyProvider(),
            executor: executor
        )
        let plan = service.buildPlan(inspection: inspection, capability: capability)
        presentPlan(
            PendingPlanContext(
                plan: plan,
                payload: .packageManager(inspection: inspection, capability: capability, service: service),
                fromMenuBar: fromMenuBar
            )
        )
    }

    // MARK: - Exact Duplicates

    func duplicateScopePolicy() -> DuplicateScopePolicy {
        DuplicateScopePolicy(
            home: homeProvider(),
            authorizedFolders: duplicateAuthorizedRoots,
            protectedPaths: protectedPathsProvider()
        )
    }

    func chooseDuplicateFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: homeProvider(), isDirectory: true)
        panel.message = L10n.Tools.duplicatesChooseFolder
        if panel.runModal() == .OK, let url = panel.url {
            addDuplicateFolder(url: url)
        }
    }

    func addDuplicateFolder(url: URL) {
        let norm = Paths.normalized(url.path)
        let scope = duplicateScopePolicy()
        let check = scope.validateFolder(norm)
        guard check.allowed else {
            duplicatesErrorPair = (
                es: check.reasonES ?? "Carpeta no autorizada.",
                en: check.reasonEN ?? "Folder not permitted."
            )
            duplicatesRawError = nil
            return
        }
        duplicatesError = nil
        _ = url.startAccessingSecurityScopedResource()
        securityScopedDuplicateURLs[norm]?.stopAccessingSecurityScopedResource()
        securityScopedDuplicateURLs[norm] = url
        if !duplicateAuthorizedRoots.contains(norm) {
            duplicateAuthorizedRoots.append(norm)
        }
    }

    func removeDuplicateFolder(_ path: String) {
        duplicateAuthorizedRoots.removeAll { $0 == path }
        securityScopedDuplicateURLs.removeValue(forKey: path)?.stopAccessingSecurityScopedResource()
    }

    func scanDuplicates() {
        guard !isScanningDuplicates else { return }
        let scope = duplicateScopePolicy()
        isScanningDuplicates = true
        duplicatesError = nil
        duplicateProgress = nil
        duplicatesCancellation?.cancel()
        let flag = CancellationFlag()
        duplicatesCancellation = flag
        duplicatesGeneration &+= 1
        let gen = duplicatesGeneration

        Task { @MainActor [weak self] in
            let (progressStream, progressContinuation) = AsyncStream.makeStream(of: DuplicateScanProgress.self)
            let progressTask = Task { @MainActor [weak self] in
                var lastPublishNs: UInt64 = 0
                var lastStage: DuplicateScanStage?
                let throttleNs: UInt64 = 90_000_000
                for await progress in progressStream {
                    guard let self, self.duplicatesGeneration == gen, !flag.isCancelled else { break }
                    let nowNs = DispatchTime.now().uptimeNanoseconds
                    let stageChanged = lastStage != progress.stage
                    let isFinalFile = progress.totalCandidateFiles > 0 && progress.hashedFiles >= progress.totalCandidateFiles
                    if stageChanged || isFinalFile || nowNs &- lastPublishNs >= throttleNs {
                        lastPublishNs = nowNs
                        lastStage = progress.stage
                        self.duplicateProgress = progress
                    }
                }
            }
            let report = await Task.detached(priority: .utility) {
                defer { progressContinuation.finish() }
                let control = ScanControl(cancellation: flag, deadline: Date().addingTimeInterval(60))
                return ExactDuplicateScanner.scan(scope: scope, control: control) { progress in
                    progressContinuation.yield(progress)
                }
            }.value
            _ = await progressTask.result
            guard let self, self.duplicatesGeneration == gen, !flag.isCancelled else {
                if let self, self.duplicatesGeneration == gen {
                    self.isScanningDuplicates = false
                }
                return
            }
            self.duplicateReport = report
            var newKept: [String: String] = [:]
            for group in report.groups {
                if let existingKept = self.duplicateKeptCopyByGroup[group.id],
                   group.files.contains(where: { $0.path == existingKept }) {
                    newKept[group.id] = existingKept
                } else {
                    newKept[group.id] = group.suggestedProtectedPath
                }
            }
            self.duplicateKeptCopyByGroup = newKept
            let allPaths = Set(report.groups.flatMap(\.files).map(\.path))
            self.duplicateSelectedDeletePaths = self.duplicateSelectedDeletePaths
                .intersection(allPaths)
                .subtracting(Set(newKept.values))
            if let first = report.groups.first, self.expandedDuplicateGroupIDs.isEmpty {
                self.expandedDuplicateGroupIDs.insert(first.id)
            }
            self.isScanningDuplicates = false
        }
    }

    func setProtectedCopy(for group: DuplicateGroup, path: String) {
        duplicateKeptCopyByGroup[group.id] = path
        duplicateSelectedDeletePaths.remove(path)
    }

    func toggleDuplicateCopy(_ file: DuplicateFileEntry, in group: DuplicateGroup) {
        let keptPath = duplicateKeptCopyByGroup[group.id] ?? group.suggestedProtectedPath
        guard file.path != keptPath else { return }
        if duplicateSelectedDeletePaths.contains(file.path) {
            duplicateSelectedDeletePaths.remove(file.path)
        } else {
            duplicateSelectedDeletePaths.insert(file.path)
        }
    }

    func selectSurplusCopiesForAllGroups() {
        guard let groups = duplicateReport?.groups else { return }
        var next = Set<String>()
        for group in groups {
            let kept = duplicateKeptCopyByGroup[group.id] ?? group.suggestedProtectedPath
            for file in group.files where file.path != kept {
                next.insert(file.path)
            }
        }
        duplicateSelectedDeletePaths = next
    }

    func duplicateSelectionTotals() -> (selectedBytes: Int64, reclaimableBytes: Int64) {
        guard let groups = duplicateReport?.groups else { return (0, 0) }
        var selected: Int64 = 0
        var reclaimed: Int64 = 0
        for group in groups {
            let kept = duplicateKeptCopyByGroup[group.id] ?? group.suggestedProtectedPath
            let deletePaths = group.files
                .map(\.path)
                .filter { duplicateSelectedDeletePaths.contains($0) && $0 != kept }
            guard !deletePaths.isEmpty else { continue }
            for file in group.files where deletePaths.contains(file.path) {
                selected += max(file.allocatedBytes, file.logicalBytes)
            }
            reclaimed += group.estimatedReclaimableBytes(deletingPaths: Set(deletePaths), protectedPath: kept)
        }
        return (selected, reclaimed)
    }

    func prepareDuplicatesPlan(fromMenuBar: Bool) {
        guard let journal = resolvedJournal(), let report = duplicateReport else { return }
        let scope = duplicateScopePolicy()
        let cleaner = DuplicateCleaner(journal: journal, scope: scope, home: homeProvider(), mover: trashMover)
        var groupSelections: [DuplicateGroupSelection] = []
        for group in report.groups {
            let kept = duplicateKeptCopyByGroup[group.id] ?? group.suggestedProtectedPath
            let surplus = group.files.map(\.path).filter { duplicateSelectedDeletePaths.contains($0) && $0 != kept }
            if !surplus.isEmpty {
                groupSelections.append(DuplicateGroupSelection(group: group, protectedFilePath: kept, surplusFilePaths: surplus))
            }
        }
        let plan = cleaner.buildPlan(selections: groupSelections)
        presentPlan(
            PendingPlanContext(
                plan: plan,
                payload: .exactDuplicates(selections: groupSelections, scope: scope),
                fromMenuBar: fromMenuBar
            )
        )
    }

    // MARK: - Application Uninstaller

    private func sharedUninstaller(
        journal: Journal,
        home: String,
        protectedPaths: [String],
        readPolicy: ReadAuthorizationPolicy
    ) -> AppUninstaller {
        let key = "\(home)|\(protectedPaths.joined(separator: ","))|\(readPolicy.projectRoots.joined(separator: ","))"
        if cachedUninstallerConfigKey == key, let existing = cachedUninstaller {
            return existing
        }
        let created = AppUninstaller(
            journal: journal,
            home: home,
            protectedPaths: protectedPaths,
            readPolicy: readPolicy,
            mover: trashMover
        )
        cachedUninstallerConfigKey = key
        cachedUninstaller = created
        return created
    }

    func inspectApplication(_ app: ApplicationItem) {
        selectedAppID = app.id
        isInspectingApp = true
        appUninstallError = nil
        let home = homeProvider()
        let protected = protectedPathsProvider()
        let policy = readPolicyProvider()
        let allApps = allInstalledAppPathsProvider()

        appInspectCancellation?.cancel()
        let flag = CancellationFlag()
        appInspectCancellation = flag
        appInspectionGeneration &+= 1
        let gen = appInspectionGeneration

        guard let journal = resolvedJournal() else {
            isInspectingApp = false
            appUninstallError = "Journal unavailable"
            return
        }

        let uninstaller = sharedUninstaller(
            journal: journal,
            home: home,
            protectedPaths: protected,
            readPolicy: policy
        )
        let bundlePath = app.url.path
        Task { @MainActor [weak self] in
            let inspection = await Task.detached(priority: .utility) { () -> AppUninstallInspection? in
                guard !flag.isCancelled else { return nil }
                return uninstaller.inspect(appBundlePath: bundlePath, otherInstalledAppPaths: allApps)
            }.value
            guard let self, self.appInspectionGeneration == gen, !flag.isCancelled, let inspection else {
                if let self, self.appInspectionGeneration == gen {
                    self.isInspectingApp = false
                }
                return
            }
            self.inspectedApp = inspection
            let defaultIDs = inspection.relatedItems
                .filter { $0.defaultSelected && !$0.requiresPrivileges }
                .map(\.id)
            self.selectedUninstallItemIDs = Set(defaultIDs)
            self.isInspectingApp = false
        }
    }

    func quitRunningInspectedApp() {
        guard let inspection = inspectedApp else { return }
        for proc in inspection.runningProcesses {
            if let runningApp = NSRunningApplication(processIdentifier: proc.pid) {
                runningApp.terminate()
            }
        }
    }

    func toggleUninstallItem(_ item: AppRelatedItem) {
        guard !item.requiresPrivileges else { return }
        if selectedUninstallItemIDs.contains(item.id) {
            selectedUninstallItemIDs.remove(item.id)
        } else {
            selectedUninstallItemIDs.insert(item.id)
        }
    }

    func prepareUninstallPlan(fromMenuBar: Bool) {
        guard let journal = resolvedJournal(), let inspection = inspectedApp else { return }
        let uninstaller = AppUninstaller(
            journal: journal,
            home: homeProvider(),
            protectedPaths: protectedPathsProvider(),
            readPolicy: readPolicyProvider(),
            mover: trashMover
        )
        let plan = uninstaller.buildPlan(
            inspection: inspection,
            selectedItemIDs: selectedUninstallItemIDs,
            includeAppBundle: includeAppBundleInUninstall
        )
        presentPlan(
            PendingPlanContext(
                plan: plan,
                payload: .appUninstall(inspection: inspection),
                fromMenuBar: fromMenuBar
            )
        )
    }

    // MARK: - Docker Manager

    func inspectDocker() {
        guard !isInspectingDocker else { return }
        isInspectingDocker = true
        dockerError = nil
        let home = homeProvider()
        dockerCancellation?.cancel()
        let flag = CancellationFlag()
        dockerCancellation = flag
        dockerGeneration &+= 1
        let gen = dockerGeneration
        let manager = DockerManager(executor: executor, home: home, journal: resolvedJournal())

        Task { @MainActor [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                let control = ScanControl(cancellation: flag, deadline: Date().addingTimeInterval(25))
                return manager.inspect(control: control)
            }.value
            guard let self, self.dockerGeneration == gen, !flag.isCancelled else {
                if let self, self.dockerGeneration == gen {
                    self.isInspectingDocker = false
                }
                return
            }
            self.dockerSnapshot = snapshot
            let validContainerIDs = Set(snapshot.stoppedContainers.map(\.id))
            let validImageIDs = Set(snapshot.images.map(\.id))
            let validVolumeNames = Set(snapshot.volumes.map(\.name))
            self.selectedDockerContainerIDs = self.selectedDockerContainerIDs.intersection(validContainerIDs)
            self.selectedDockerImageIDs = self.selectedDockerImageIDs.intersection(validImageIDs)
            self.selectedDockerVolumeNames = self.selectedDockerVolumeNames.intersection(validVolumeNames)
            self.unlockedDockerVolumeNames = self.unlockedDockerVolumeNames.intersection(validVolumeNames)
            self.isInspectingDocker = false
        }
    }

    func toggleDockerContainer(_ container: DockerContainerResource) {
        guard !container.isRunning else { return }
        if selectedDockerContainerIDs.contains(container.id) {
            selectedDockerContainerIDs.remove(container.id)
        } else {
            selectedDockerContainerIDs.insert(container.id)
        }
    }

    func toggleDockerImage(_ image: DockerImageResource) {
        guard !image.isUsedByRunningContainer else { return }
        if selectedDockerImageIDs.contains(image.id) {
            selectedDockerImageIDs.remove(image.id)
        } else {
            selectedDockerImageIDs.insert(image.id)
        }
    }

    func toggleDockerVolumeLock(_ volume: DockerVolumeResource) {
        guard !volume.isMountedByRunningContainer else { return }
        if unlockedDockerVolumeNames.contains(volume.name) {
            unlockedDockerVolumeNames.remove(volume.name)
            selectedDockerVolumeNames.remove(volume.name)
        } else {
            unlockedDockerVolumeNames.insert(volume.name)
        }
    }

    func toggleDockerVolumeSelection(_ volume: DockerVolumeResource) {
        guard !volume.isMountedByRunningContainer, unlockedDockerVolumeNames.contains(volume.name) else { return }
        if selectedDockerVolumeNames.contains(volume.name) {
            selectedDockerVolumeNames.remove(volume.name)
        } else {
            selectedDockerVolumeNames.insert(volume.name)
        }
    }

    func prepareDockerPlan(fromMenuBar: Bool) {
        guard let snapshot = dockerSnapshot else { return }
        let manager = DockerManager(executor: executor, home: homeProvider(), journal: resolvedJournal())
        let selection = DockerCleanupSelection(
            containerIDs: Array(selectedDockerContainerIDs).sorted(),
            imageIDs: Array(selectedDockerImageIDs).sorted(),
            volumeNames: Array(selectedDockerVolumeNames).sorted(),
            unlockedVolumeNames: unlockedDockerVolumeNames,
            buildCacheScope: selectedDockerBuildCacheScope
        )
        let plan = manager.buildPlan(snapshot: snapshot, selection: selection)
        presentPlan(
            PendingPlanContext(
                plan: plan,
                payload: .docker(selection: selection, manager: manager),
                fromMenuBar: fromMenuBar
            )
        )
    }

    // MARK: - Unified Inventory Plan From Menu Bar

    func prepareInventoryPlan(selectedFiles: [IndexedFile], fromMenuBar: Bool) {
        guard !selectedFiles.isEmpty else { return }
        let sorted = selectedFiles.sorted { $0.path < $1.path }
        let resources = sorted.map { file in
            let presentation = InventoryItemPresentation(file: file)
            return OperationAffectedResource(
                id: file.id,
                labelES: presentation.name,
                labelEN: presentation.name,
                pathOrIdentifier: file.path,
                sizeBytes: file.allocatedBytes,
                logicalBytes: file.logicalBytes,
                sizeBasis: .measured,
                mechanism: .trash,
                blockedReasonES: file.isReviewable ? nil : presentation.explanation,
                blockedReasonEN: file.isReviewable ? nil : presentation.explanation
            )
        }
        let totalAllocated = sorted.reduce(Int64(0)) { ByteTotals.adding($0, $1.allocatedBytes) }
        let totalLogical = sorted.reduce(Int64(0)) { ByteTotals.adding($0, $1.logicalBytes) }
        let plan = OperationPlan(
            domain: .cacheInventory,
            titleES: "Mover selección de inventario a la Papelera",
            titleEN: "Move selected inventory items to Trash",
            scopeDescriptionES: "\(sorted.count) elemento(s) elegible(s) seleccionados de las categorías escaneadas.",
            scopeDescriptionEN: "\(sorted.count) eligible item(s) selected from scanned categories.",
            affectedResources: resources,
            preservedSummaryES: "Se conservan los archivos fuera de la selección, los bloqueados y la propia Papelera (Brisa nunca la vacía).",
            preservedSummaryEN: "Unselected items, protected files, and Trash contents are preserved (Brisa never empties Trash).",
            totalBytes: totalAllocated,
            logicalBytes: totalLogical,
            sizeBasis: .measured,
            sizeNoteES: "Espacio asignado en disco; en APFS los bloques permanecen en ~/.Trash hasta vaciar la Papelera en Finder.",
            sizeNoteEN: "Measured allocated disk bytes; on APFS blocks stay in ~/.Trash until Trash is emptied in Finder.",
            regenerationES: "Las aplicaciones regeneran sus cachés y registros automáticamente cuando las vuelves a abrir.",
            regenerationEN: "Applications regenerate their caches and logs automatically the next time you run them.",
            mechanism: .trash,
            restorability: .trashRestore,
            restorabilityNoteES: "Admite restauración desde la Papelera si los elementos permanecen allí y la ruta original está libre.",
            restorabilityNoteEN: "Restorable from Trash if the items remain there and the original destination is free.",
            blockers: [],
            canExecute: true
        )
        presentPlan(
            PendingPlanContext(
                plan: plan,
                payload: .inventoryFiles(ids: sorted.map(\.id)),
                fromMenuBar: fromMenuBar
            )
        )
    }

    // MARK: - Plan Presentation, Recheck, & Execution

    func presentPlan(_ context: PendingPlanContext) {
        pendingPlanContext = context
        dockerVolumeConfirmationChecked = !context.plan.requiresExplicitVolumeUnlock
        lastExecutionReport = nil
        if context.fromMenuBar {
            pushMenuRoute(.reviewPlan)
        } else {
            showMenuPlanSheetInWindow = true
        }
    }

    func dismissPlanReview() {
        recheckCancellation?.cancel()
        recheckCancellation = nil
        recheckGeneration &+= 1
        isRecheckingPlan = false
        showMenuPlanSheetInWindow = false
        if menuRoute == .reviewPlan || menuRoute == .executionResult {
            popMenuRoute()
        }
        pendingPlanContext = nil
        lastExecutionReport = nil
    }

    func recheckPendingPlan() {
        guard let context = pendingPlanContext, !isExecutingPlan else { return }
        recheckCancellation?.cancel()
        let flag = CancellationFlag()
        recheckCancellation = flag
        recheckGeneration &+= 1
        let gen = recheckGeneration
        let contextID = context.id

        switch context.payload {
        case let .projectArtifacts(_, _, cleaner):
            let policy = projectPolicy()
            let selectedIDs = selectedProjectArtifactIDs
            let existingArtifacts = projectGroups.flatMap(\.artifacts).filter { selectedIDs.contains($0.id) }
            isRecheckingPlan = true
            Task { @MainActor [weak self] in
                let newPlan = await Task.detached(priority: .userInitiated) {
                    policy.buildPlan(selectedArtifacts: existingArtifacts)
                }.value
                guard let self,
                      self.recheckGeneration == gen,
                      !flag.isCancelled,
                      self.pendingPlanContext?.id == contextID else {
                    if let self, self.recheckGeneration == gen {
                        self.isRecheckingPlan = false
                    }
                    return
                }
                self.pendingPlanContext = PendingPlanContext(
                    plan: newPlan,
                    payload: .projectArtifacts(targets: existingArtifacts, policy: policy, cleaner: cleaner),
                    fromMenuBar: context.fromMenuBar
                )
                self.isRecheckingPlan = false
            }

        case let .packageManager(inspection, capability, service):
            isRecheckingPlan = true
            Task { @MainActor [weak self] in
                let result = await Task.detached(priority: .userInitiated) { () -> (PackageManagerInspection, PackageManagerOperationCapability, OperationPlan)? in
                    let control = ScanControl(cancellation: flag, deadline: Date().addingTimeInterval(25))
                    let all = service.inspectAll(control: control)
                    guard !flag.isCancelled else { return nil }
                    let refreshed = all.first(where: { $0.kind == inspection.kind }) ?? inspection
                    let refreshedCap = refreshed.capabilities.first(where: { $0.id == capability.id }) ?? capability
                    let newPlan = service.buildPlan(inspection: refreshed, capability: refreshedCap)
                    return (refreshed, refreshedCap, newPlan)
                }.value
                guard let self,
                      self.recheckGeneration == gen,
                      !flag.isCancelled,
                      self.pendingPlanContext?.id == contextID,
                      let (refreshed, refreshedCap, newPlan) = result else {
                    if let self, self.recheckGeneration == gen {
                        self.isRecheckingPlan = false
                    }
                    return
                }
                self.pendingPlanContext = PendingPlanContext(
                    plan: newPlan,
                    payload: .packageManager(inspection: refreshed, capability: refreshedCap, service: service),
                    fromMenuBar: context.fromMenuBar
                )
                self.isRecheckingPlan = false
            }

        case .exactDuplicates:
            prepareDuplicatesPlan(fromMenuBar: context.fromMenuBar)

        case let .appUninstall(inspection):
            guard let journal = resolvedJournal() else { return }
            let uninstaller = sharedUninstaller(
                journal: journal,
                home: homeProvider(),
                protectedPaths: protectedPathsProvider(),
                readPolicy: readPolicyProvider()
            )
            let allApps = allInstalledAppPathsProvider()
            let bundlePath = inspection.app.bundlePath
            let selectedIDs = selectedUninstallItemIDs
            let includeBundle = includeAppBundleInUninstall
            isRecheckingPlan = true

            Task { @MainActor [weak self] in
                let result = await Task.detached(priority: .userInitiated) { () -> (AppUninstallInspection, OperationPlan)? in
                    guard !flag.isCancelled else { return nil }
                    let refreshed = uninstaller.inspect(appBundlePath: bundlePath, otherInstalledAppPaths: allApps)
                    guard !flag.isCancelled else { return nil }
                    let newPlan = uninstaller.buildPlan(
                        inspection: refreshed,
                        selectedItemIDs: selectedIDs,
                        includeAppBundle: includeBundle
                    )
                    return (refreshed, newPlan)
                }.value
                guard let self,
                      self.recheckGeneration == gen,
                      !flag.isCancelled,
                      self.pendingPlanContext?.id == contextID,
                      let (refreshed, newPlan) = result else {
                    if let self, self.recheckGeneration == gen {
                        self.isRecheckingPlan = false
                    }
                    return
                }
                self.inspectedApp = refreshed
                self.pendingPlanContext = PendingPlanContext(
                    plan: newPlan,
                    payload: .appUninstall(inspection: refreshed),
                    fromMenuBar: context.fromMenuBar
                )
                self.isRecheckingPlan = false
            }

        case let .docker(selection, manager):
            isRecheckingPlan = true
            Task { @MainActor [weak self] in
                let result = await Task.detached(priority: .userInitiated) { () -> (DockerInspectionSnapshot, OperationPlan)? in
                    let control = ScanControl(cancellation: flag, deadline: Date().addingTimeInterval(25))
                    let refreshed = manager.inspect(control: control)
                    guard !flag.isCancelled else { return nil }
                    let newPlan = manager.buildPlan(snapshot: refreshed, selection: selection)
                    return (refreshed, newPlan)
                }.value
                guard let self,
                      self.recheckGeneration == gen,
                      !flag.isCancelled,
                      self.pendingPlanContext?.id == contextID,
                      let (refreshed, newPlan) = result else {
                    if let self, self.recheckGeneration == gen {
                        self.isRecheckingPlan = false
                    }
                    return
                }
                self.dockerSnapshot = refreshed
                self.pendingPlanContext = PendingPlanContext(
                    plan: newPlan,
                    payload: .docker(selection: selection, manager: manager),
                    fromMenuBar: context.fromMenuBar
                )
                self.isRecheckingPlan = false
            }

        case .inventoryFiles:
            break
        }
    }

    func executePendingPlan() {
        guard let context = pendingPlanContext, !isExecutingPlan else { return }
        guard context.plan.canExecute else { return }
        if context.plan.requiresExplicitVolumeUnlock && !dockerVolumeConfirmationChecked { return }

        isExecutingPlan = true
        executionCancellation?.cancel()
        let flag = CancellationFlag()
        executionCancellation = flag
        let home = homeProvider()
        let protected = protectedPathsProvider()
        let policy = readPolicyProvider()
        let mover = trashMover

        Task { @MainActor [weak self] in
            guard let self else { return }
            let report: OperationExecutionReport
            switch context.payload {
            case let .inventoryFiles(ids):
                report = await self.trashInventoryExecutor(ids) ?? OperationExecutionReport(
                    planID: context.plan.id,
                    domain: .cacheInventory,
                    outcome: .failed,
                    mechanism: .trash,
                    restorable: false,
                    summaryES: "No se pudo iniciar la operación en la Papelera.",
                    summaryEN: "Unable to start Trash operation."
                )

            case let .projectArtifacts(targets, _, cleaner):
                report = await Task.detached(priority: .userInitiated) {
                    do {
                        return try cleaner.execute(plan: context.plan, targets: targets, cancellation: flag)
                    } catch {
                        return Self.failedReport(plan: context.plan, error: error)
                    }
                }.value
                self.scanProjects()

            case let .packageManager(inspection, capability, service):
                report = await Task.detached(priority: .userInitiated) {
                    do {
                        return try service.execute(
                            plan: context.plan,
                            inspection: inspection,
                            capability: capability,
                            cancellation: flag
                        )
                    } catch {
                        return Self.failedReport(plan: context.plan, error: error)
                    }
                }.value
                self.scanPackageManagers()

            case let .exactDuplicates(selections, scope):
                let journal = self.resolvedJournal()
                report = await Task.detached(priority: .userInitiated) {
                    guard let journal else {
                        return Self.failedReport(plan: context.plan, error: BrisaError.unavailable("Journal unavailable"))
                    }
                    let cleaner = DuplicateCleaner(journal: journal, scope: scope, home: home, mover: mover)
                    do {
                        return try cleaner.execute(plan: context.plan, selections: selections, cancellation: flag)
                    } catch {
                        return Self.failedReport(plan: context.plan, error: error)
                    }
                }.value
                if let groups = self.duplicateReport?.groups, !groups.isEmpty {
                    self.scanDuplicates()
                }

            case let .appUninstall(inspection):
                let journal = self.resolvedJournal()
                report = await Task.detached(priority: .userInitiated) {
                    guard let journal else {
                        return Self.failedReport(plan: context.plan, error: BrisaError.unavailable("Journal unavailable"))
                    }
                    let uninstaller = AppUninstaller(
                        journal: journal,
                        home: home,
                        protectedPaths: protected,
                        readPolicy: policy,
                        mover: mover
                    )
                    do {
                        return try uninstaller.execute(plan: context.plan, inspection: inspection, cancellation: flag)
                    } catch {
                        return Self.failedReport(plan: context.plan, error: error)
                    }
                }.value
                if let app = self.inspectedApp?.app {
                    let item = ApplicationItem(url: URL(fileURLWithPath: app.bundlePath))
                    if FileManager.default.fileExists(atPath: app.bundlePath) {
                        self.inspectApplication(item)
                    } else {
                        self.inspectedApp = nil
                        self.selectedUninstallItemIDs.removeAll()
                    }
                }

            case let .docker(selection, manager):
                let dockerResult: Result<DockerCleanupExecutionResult, Error> = await Task.detached(priority: .userInitiated) {
                    do {
                        return .success(try manager.execute(plan: context.plan, selection: selection, control: ScanControl(cancellation: flag)))
                    } catch {
                        return .failure(error)
                    }
                }.value
                switch dockerResult {
                case let .success(res):
                    report = res.report
                    self.selectedDockerContainerIDs.subtract(res.removedContainerIDs)
                    self.selectedDockerImageIDs.subtract(res.removedImageIDs)
                    self.selectedDockerVolumeNames.subtract(res.removedVolumeNames)
                    if res.prunedBuildCacheScope != nil {
                        self.selectedDockerBuildCacheScope = nil
                    }
                case let .failure(err):
                    report = Self.failedReport(plan: context.plan, error: err)
                }
                self.inspectDocker()
            }

            if self.executionCancellation === flag {
                self.executionCancellation = nil
            }
            self.lastExecutionReport = report
            self.isExecutingPlan = false
            self.onJournalUpdated()
            if context.fromMenuBar && !flag.isCancelled {
                self.menuRoute = .executionResult
            }
        }
    }

    // MARK: - Helpers

    func openInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func resolvedJournal() -> Journal? {
        if let existing = journalProvider() {
            return existing
        }
        let dir = URL(fileURLWithPath: homeProvider(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/Brisa", isDirectory: true)
        guard let store = try? PrivateStore(directory: dir) else { return nil }
        return Journal(store: store)
    }

    private nonisolated static func failedReport(plan: OperationPlan, error: Error) -> OperationExecutionReport {
        OperationExecutionReport(
            planID: plan.id,
            domain: plan.domain,
            outcome: .failed,
            mechanism: plan.mechanism,
            restorable: false,
            failedItems: plan.affectedResources.map(\.pathOrIdentifier),
            summaryES: error.localizedDescription,
            summaryEN: error.localizedDescription
        )
    }
}
