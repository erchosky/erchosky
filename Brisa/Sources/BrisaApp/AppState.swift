import SwiftUI
import AppKit
import UserNotifications
import BrisaCore

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    var title: String {
        switch self {
        case .system: return L10n.Common.appearanceSystem
        case .light: return L10n.Common.appearanceLight
        case .dark: return L10n.Common.appearanceDark
        }
    }
    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
    static func normalized(_ raw: String?) -> String {
        guard let raw, Self(rawValue: raw) != nil else { return Self.system.rawValue }
        return raw
    }
}

enum CleanWorkspaceMode: String, CaseIterable, Identifiable {
    case candidates
    case explore
    case duplicates
    case advanced

    var id: String { rawValue }
}

enum Page: String, CaseIterable, Identifiable {
    case overview, findings, applications, activity, settings

    static var primaryPages: [Page] { [.overview, .findings, .applications, .activity] }

    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return L10n.Common.navOverview
        case .findings: return L10n.Common.navFindings
        case .applications: return L10n.Common.navApplications
        case .activity: return L10n.Common.navActivity
        case .settings: return L10n.Common.navSettings
        }
    }
    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .findings: return "sparkles"
        case .applications: return "app.dashed"
        case .activity: return "clock.arrow.circlepath"
        case .settings: return "slider.horizontal.3"
        }
    }
}

struct ApplicationItem: Identifiable {
    let url: URL
    var id: String { url.path }
    var name: String { url.deletingPathExtension().lastPathComponent }
    let bundleID: String?
    init(url: URL) {
        self.url = url
        self.bundleID = Bundle(url: url)?.bundleIdentifier
    }
}

struct JournalSummary: Equatable {
    var trashedBytes: Int64 = 0
    var trashedCount: Int = 0
    var restoredBytes: Int64 = 0
    var restoredCount: Int = 0
    var rejectedBytes: Int64 = 0
    var rejectedCount: Int = 0
    var plannedCount: Int = 0
    var completedPlansCount: Int = 0
    var partialOrFailedCount: Int = 0
    var latestFreeSpaceDelta: Int64?

    static func compute(from entries: [JournalEntry]) -> JournalSummary {
        var summary = JournalSummary()
        summary.latestFreeSpaceDelta = entries.first?.freeSpaceDelta
        let planIDsWithItemEntries = Set(entries.compactMap { entry in
            entry.id.hasPrefix("plan-") ? nil : entry.planID
        })
        for entry in entries {
            let size = entry.allocatedBytes ?? entry.size
            if entry.id.hasPrefix("plan-") {
                let planKey = entry.planID ?? String(entry.id.dropFirst("plan-".count))
                let hasItemEntries = planIDsWithItemEntries.contains(planKey)
                let outcome = entry.outcomeKind ?? entry.status
                switch outcome {
                case "planned":
                    summary.plannedCount += 1
                case "completed":
                    summary.completedPlansCount += 1
                case "partial", "failed":
                    summary.partialOrFailedCount += 1
                    if !hasItemEntries {
                        summary.rejectedCount += 1
                    }
                case "rejected", "cancelled":
                    summary.partialOrFailedCount += 1
                    if !hasItemEntries {
                        summary.rejectedBytes = ByteTotals.adding(summary.rejectedBytes, size)
                        summary.rejectedCount += 1
                    }
                default:
                    break
                }
            } else {
                switch entry.status {
                case "trashed":
                    summary.trashedBytes = ByteTotals.adding(summary.trashedBytes, size)
                    summary.trashedCount += 1
                case "restored":
                    summary.restoredBytes = ByteTotals.adding(summary.restoredBytes, size)
                    summary.restoredCount += 1
                case "rejected", "cancelled", "failed":
                    summary.rejectedBytes = ByteTotals.adding(summary.rejectedBytes, size)
                    summary.rejectedCount += 1
                default:
                    let fallback = entry.outcomeKind ?? entry.status
                    if fallback == "rejected" || fallback == "cancelled" || fallback == "failed" {
                        summary.rejectedBytes = ByteTotals.adding(summary.rejectedBytes, size)
                        summary.rejectedCount += 1
                    }
                }
            }
        }
        return summary
    }
}

private final class ResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: IPCResponse?
    func set(_ value: IPCResponse) { lock.lock(); self.value = value; lock.unlock() }
    func get() -> IPCResponse? { lock.lock(); defer { lock.unlock() }; return value }
}

private final class ScanProgressCoalescer: @unchecked Sendable {
    private let lock = NSLock()
    private var lastDispatchedUptime: UInt64 = 0
    private var lastCompletedCategories = -1
    private let intervalNanoseconds: UInt64 = 100_000_000

    func shouldEmit(_ progress: ScanProgress) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = DispatchTime.now().uptimeNanoseconds
        let completedChanged = progress.completedCategories != lastCompletedCategories
        if completedChanged || now &- lastDispatchedUptime >= intervalNanoseconds {
            lastDispatchedUptime = now
            lastCompletedCategories = progress.completedCategories
            return true
        }
        return false
    }
}

/// Holds nonisolated handles so `deinit` can stop background services safely without actor-isolation errors.
private final class LifecycleResources: @unchecked Sendable {
    private let lock = NSLock()
    var server: IPCServer?
    var cancellation = CancellationFlag()
    var operationCancellation = CancellationFlag()
    var startupTask: Task<Void, Never>?
    var scanTask: Task<Void, Never>?
    var agentsTask: Task<Void, Never>?
    var applicationsTask: Task<Void, Never>?

    func shutdown() {
        lock.lock()
        let activeServer = server
        server = nil
        let activeStartup = startupTask
        startupTask = nil
        let activeScan = scanTask
        scanTask = nil
        let activeAgents = agentsTask
        agentsTask = nil
        let activeApps = applicationsTask
        applicationsTask = nil
        let scanFlag = cancellation
        let opFlag = operationCancellation
        lock.unlock()

        scanFlag.cancel()
        opFlag.cancel()
        activeStartup?.cancel()
        activeScan?.cancel()
        activeAgents?.cancel()
        activeApps?.cancel()
        activeServer?.stop()
    }

    deinit {
        shutdown()
    }
}

@MainActor final class AppState: ObservableObject {
    let computerName = Host.current().localizedName ?? "Mac"
    @Published var page: Page = .overview
    @Published var cleanMode: CleanWorkspaceMode = .candidates
    @Published var showAdvancedSettings = false
    let liveMetrics: LiveMetricsStore
    var hasActiveWork: Bool { operating || scanning || (tools?.hasActiveWork ?? false) }
    var metrics: MetricsSnapshot? { liveMetrics.snapshot }
    var effectiveLanguageCode: String { AppLanguage.resolve(preference: language).rawValue }
    var appLocale: Locale {
        language == AppLanguage.system.rawValue ? .current : Locale(identifier: effectiveLanguageCode)
    }
    @Published var scan = ScanResult() {
        didSet {
            filteredCache = nil
            reviewableFilteredCache = nil
            mapCache.removeAll(keepingCapacity: true)
            var index: [String: IndexedFile] = [:]
            index.reserveCapacity(scan.files.count)
            var eligible: [IndexedFile] = []
            var byCategory: [StorageCategory: [IndexedFile]] = [:]
            var eligibleByCategory: [StorageCategory: [IndexedFile]] = [:]
            var allocatedTotal: Int64 = 0
            var logicalTotal: Int64 = 0
            var candidateTotal: Int64 = 0
            var reclaimableTotal: Int64 = 0
            for file in scan.files {
                index[file.id] = file
                byCategory[file.storageCategory, default: []].append(file)
                allocatedTotal = ByteTotals.adding(allocatedTotal, file.allocatedBytes)
                logicalTotal = ByteTotals.adding(logicalTotal, file.logicalBytes)
                if file.isReviewable {
                    eligible.append(file)
                    eligibleByCategory[file.storageCategory, default: []].append(file)
                    candidateTotal = ByteTotals.adding(candidateTotal, file.size)
                    reclaimableTotal = ByteTotals.adding(reclaimableTotal, file.allocatedBytes)
                }
            }
            let byAllocatedDesc: (IndexedFile, IndexedFile) -> Bool = {
                if $0.allocatedBytes != $1.allocatedBytes { return $0.allocatedBytes > $1.allocatedBytes }
                return $0.path < $1.path
            }
            for cat in byCategory.keys {
                byCategory[cat]?.sort(by: byAllocatedDesc)
            }
            for cat in eligibleByCategory.keys {
                eligibleByCategory[cat]?.sort(by: byAllocatedDesc)
            }
            fileIndex = index
            eligibleCache = eligible
            sortedEligibleCache = eligible.sorted(by: byAllocatedDesc)
            filesByCategoryCache = byCategory
            eligibleByCategoryCache = eligibleByCategory
            cachedMeasuredBytes = allocatedTotal
            cachedLogicalBytes = logicalTotal
            cachedCandidateBytes = candidateTotal
            cachedReclaimableAllocatedBytes = reclaimableTotal
        }
    }
    @Published var categories: [CategoryReport] = CategoryReport.defaultPending()
    @Published var scanProgress = ScanProgress()
    @Published var selected = Set<String>()
    @Published var scanning = false
    @Published var operating = false
    @Published var preferences = Preferences()
    @Published var activity: [ActivityEntry] = []
    @Published var journalEntries: [JournalEntry] = [] {
        didSet { journalSummary = JournalSummary.compute(from: journalEntries) }
    }
    private(set) var journalSummary = JournalSummary()
    @Published var agents: [AgentInfo] = []
    @Published var applications: [ApplicationItem] = []
    @Published var applicationsScanIncomplete = false
    @Published var conclusions: [AgentConclusion] = []
    @Published var orphanBuilds: [OrphanBuildAssessment] = []
    @Published var worktrees: [WorktreeAuditEntry] = []
    @Published var projectArtifacts: [ProjectArtifactAuditEntry] = []
    @Published var contextualScanStatus = "pending"
    @Published var contextualScanNotes: [String] = []

    // Filtering, sorting & space map navigation state
    @Published var query = ""
    @Published var category = "all"
    @Published var sizeFilter = "all"       // "all", "gt10m", "gt100m", "gt1g", "zero_allocated"
    @Published var typeFilter = "all"       // "all", "file", "directory"
    @Published var statusFilter = "all"     // "all", "eligible", "inventory", "in_use", "partial"
    @Published var dateFilter = "all"       // "all", "lt24h", "gt7d", "gt30d"
    @Published var locationFilter = "all"   // "all", "library", "hidden", "projects"
    @Published var sortOrder = "allocated_desc" // "allocated_desc", "logical_desc", "modified_desc", "name_asc"
    @Published var spaceMapFolderPrefix: String? = nil

    @Published var lastError: String?
    @Published var showPalette = false
    @Published private var notificationAuthorization: Bool?
    var permissionStatus: String {
        guard let allowed = notificationAuthorization else { return L10n.Settings.notificationsNotRequested }
        return allowed ? L10n.Settings.notificationsAuthorized : L10n.Settings.notificationsNotAuthorized
    }
    @Published var language: String = AppLanguage.system.rawValue {
        didSet {
            let valid = AppLanguage.sanitizedPreference(language)
            if language != valid {
                language = valid
                return
            }
            guard hasCompletedInit else { return }
            defaults.set(valid, forKey: "BrisaLanguage")
            L10n.setPreference(valid)
            preferences.language = valid
            if liveMetrics.isMenuVisible {
                liveMetrics.refreshBreakdown()
            }
            do { try savePreferences() } catch { fail(error) }
        }
    }
    @Published var appearance: String = AppAppearance.system.rawValue {
        didSet {
            let valid = AppAppearance.normalized(appearance)
            if appearance != valid {
                appearance = valid
                return
            }
            guard hasCompletedInit else { return }
            defaults.set(valid, forKey: "BrisaAppearance")
            preferences.appearance = valid
            applyAppearance()
            do { try savePreferences() } catch { fail(error) }
        }
    }
    @Published var showMenuBarFreeSpace: Bool = false {
        didSet {
            guard hasCompletedInit else { return }
            defaults.set(showMenuBarFreeSpace, forKey: "BrisaShowMenuBarFreeSpace")
            preferences.showMenuBarFreeSpace = showMenuBarFreeSpace
            liveMetrics.setStatusBarMonitoring(showMenuBarFreeSpace)
            do { try savePreferences() } catch { fail(error) }
        }
    }
    @Published var welcomed: Bool = false

    var appearanceMode: AppAppearance { AppAppearance(rawValue: appearance) ?? .system }
    var preferredColorScheme: ColorScheme? { appearanceMode.colorScheme }

    private let defaults: UserDefaults
    private let homeDirectory: String
    private let lifecycle = LifecycleResources()
    private var hasCompletedInit = false

    private var cancellation: CancellationFlag {
        get { lifecycle.cancellation }
        set { lifecycle.cancellation = newValue }
    }
    private var operationCancellation: CancellationFlag {
        get { lifecycle.operationCancellation }
        set { lifecycle.operationCancellation = newValue }
    }
    private var scanGeneration = UUID()
    private var fileIndex: [String: IndexedFile] = [:]
    private var loadingApplications = false
    private var hasLoadedApplications = false
    private var applicationRemnantsByID: [String: [String]] = [:]
    private var authorizedInventoryURLs: [String: URL] = [:]
    private var eligibleCache: [IndexedFile] = []
    private var sortedEligibleCache: [IndexedFile] = []
    private var filesByCategoryCache: [StorageCategory: [IndexedFile]] = [:]
    private var eligibleByCategoryCache: [StorageCategory: [IndexedFile]] = [:]
    private var cachedMeasuredBytes: Int64 = 0
    private var cachedLogicalBytes: Int64 = 0
    private var cachedCandidateBytes: Int64 = 0
    private var cachedReclaimableAllocatedBytes: Int64 = 0
    struct FilteredInventorySummary {
        let query: InventoryQuery
        let files: [IndexedFile]
        let byCategory: [StorageCategory: [IndexedFile]]
        let allocated: Int64
        let logical: Int64
        let hasPartial: Bool
        let hasReviewable: Bool
    }
    private var filteredCache: FilteredInventorySummary?
    private var reviewableFilteredCache: FilteredInventorySummary?
    private struct MapKey: Hashable {
        let category: StorageCategory?
        let folder: String?
        let language: String
        let query: InventoryQuery?
    }
    private var mapCache: [MapKey: SpaceMapSlice] = [:]
    private var store: PrivateStore?
    private var journal: Journal?
    private var operations: TrashOperations?
    private var server: IPCServer? {
        get { lifecycle.server }
        set { lifecycle.server = newValue }
    }
    var revealWindow: (() -> Void)?
    private(set) var tools: ToolsCoordinator!

    convenience init() {
        self.init(
            userDefaults: .standard,
            storeURL: nil,
            ipcSocketPath: nil,
            homeDirectory: NSHomeDirectory(),
            startServices: true
        )
    }

    init(
        userDefaults: UserDefaults,
        storeURL: URL? = nil,
        ipcSocketPath: String? = nil,
        homeDirectory: String = NSHomeDirectory(),
        startServices: Bool = true,
        commandExecutor: any CommandExecuting = LiveCommandExecutor(),
        trashMover: any TrashMoving = SystemTrashMover()
    ) {
        self.defaults = userDefaults
        self.homeDirectory = homeDirectory
        self.liveMetrics = LiveMetricsStore(observeLifecycle: startServices)
        self.welcomed = userDefaults.bool(forKey: "BrisaWelcomed")

        var initialLanguage = AppLanguage.sanitizedPreference(userDefaults.string(forKey: "BrisaLanguage"))
        var initialAppearance = AppAppearance.normalized(userDefaults.string(forKey: "BrisaAppearance"))
        var initialShowMenuBar = userDefaults.bool(forKey: "BrisaShowMenuBarFreeSpace")

        do {
            let store = try PrivateStore(directory: storeURL)
            self.store = store
            let savedPreferences = try store.read("preferences.json", as: Preferences.self)
            preferences = savedPreferences ?? Preferences()
            if savedPreferences == nil {
                preferences.roots = ["Library/Caches", "Library/Logs"]
                    .map { homeDirectory + "/" + $0 }
                    .filter { FileManager.default.fileExists(atPath: $0) }
                preferences.inventoryRoots = ["Developer", "Projects", "Code", "Work", "Repos"]
                    .map { homeDirectory + "/" + $0 }
                    .filter { FileManager.default.fileExists(atPath: $0) }
                preferences.appearance = initialAppearance
                preferences.language = initialLanguage
                preferences.showMenuBarFreeSpace = initialShowMenuBar
                try store.write("preferences.json", value: preferences)
            } else {
                if userDefaults.string(forKey: "BrisaAppearance") == nil {
                    initialAppearance = AppAppearance.normalized(preferences.appearance)
                } else {
                    preferences.appearance = initialAppearance
                }
                if userDefaults.object(forKey: "BrisaShowMenuBarFreeSpace") == nil {
                    initialShowMenuBar = preferences.showMenuBarFreeSpace
                } else {
                    preferences.showMenuBarFreeSpace = initialShowMenuBar
                }
            }
            if userDefaults.string(forKey: "BrisaLanguage") == nil {
                initialLanguage = AppLanguage.sanitizedPreference(preferences.language)
            }
            preferences.language = initialLanguage
            preferences.appearance = initialAppearance
            preferences.showMenuBarFreeSpace = initialShowMenuBar

            language = initialLanguage
            appearance = initialAppearance
            showMenuBarFreeSpace = initialShowMenuBar
            L10n.setPreference(initialLanguage)
            userDefaults.set(initialLanguage, forKey: "BrisaLanguage")
            userDefaults.set(initialAppearance, forKey: "BrisaAppearance")
            userDefaults.set(initialShowMenuBar, forKey: "BrisaShowMenuBarFreeSpace")

            let journal = Journal(store: store)
            self.journal = journal
            self.operations = TrashOperations(journal: journal, mover: trashMover)

            if startServices {
                let server = IPCServer(path: ipcSocketPath ?? IPCSocket.path)
                self.server = server
                try server.start { [weak self] request in
                    let semaphore = DispatchSemaphore(value: 0), box = ResponseBox()
                    Task { @MainActor [weak self] in
                        guard let self else { box.set(IPCResponse(id: request.id, error: BrisaError.unavailable("App closing"))); semaphore.signal(); return }
                        do { box.set(IPCResponse(id: request.id, result: try await self.handle(request))) }
                        catch { box.set(IPCResponse(id: request.id, error: error)) }
                        semaphore.signal()
                    }
                    guard semaphore.wait(timeout: .now() + 115) == .success, let response = box.get() else {
                        return IPCResponse(id: request.id, error: BrisaError.unavailable("Request timed out; inspect app before retrying"))
                    }
                    return response
                }
            }
        } catch {
            language = initialLanguage
            appearance = initialAppearance
            showMenuBarFreeSpace = initialShowMenuBar
            L10n.setPreference(initialLanguage)
            lastError = error.localizedDescription
        }

        hasCompletedInit = true
        applyAppearance()
        self.tools = ToolsCoordinator(
            homeProvider: { [weak self] in self?.homeDirectory ?? NSHomeDirectory() },
            protectedPathsProvider: { [weak self] in self?.preferences.protectedPaths ?? [] },
            readPolicyProvider: { [weak self] in self?.readPolicy() ?? ReadAuthorizationPolicy() },
            inventoryRootsProvider: { [weak self] in self?.preferences.inventoryRoots ?? [] },
            allInstalledAppPathsProvider: { [weak self] in self?.applications.map(\.url.path) ?? [] },
            journalProvider: { [weak self] in self?.journal },
            trashInventoryExecutor: { [weak self] ids in
                guard let self else { return nil }
                return await self.executePreconfirmedTrash(ids: ids)
            },
            onJournalUpdated: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.reloadJournalEntries()
                }
            },
            executor: commandExecutor,
            trashMover: trashMover
        )

        if startServices {
            liveMetrics.setStatusBarMonitoring(showMenuBarFreeSpace)
            let storeRef = self.store
            let journalRef = self.journal
            lifecycle.startupTask = Task.detached(priority: .utility) { [weak self] in
                guard !Task.isCancelled else { return }
                let loadedJournal = (try? journalRef?.entries()) ?? []
                let loadedActivity = (try? storeRef?.read("activity.json", as: [ActivityEntry].self)) ?? []
                let loadedCatalog = try? CatalogLoader.load()
                let detectedAgents = AgentDiscovery.detect()
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if self.journalEntries.isEmpty && !loadedJournal.isEmpty {
                        self.journalEntries = loadedJournal
                    }
                    if !loadedActivity.isEmpty {
                        self.activity = Array((self.activity + loadedActivity).prefix(100))
                    }
                    if let source = loadedCatalog?.sourceKind, !self.scanning, self.scan.finishedAt == nil {
                        self.scan.catalogSource = source
                    }
                    if self.agents.isEmpty {
                        self.agents = detectedAgents
                    }
                }
            }
        }
    }

    /// Cancels active background tasks, stops telemetry polling and closes the IPC socket.
    func shutdown() {
        // Detached scans can finish after cancellation; invalidate their publication token first.
        scanGeneration = UUID()
        tools?.cancelAllActiveWork()
        for (_, url) in authorizedInventoryURLs {
            url.stopAccessingSecurityScopedResource()
        }
        authorizedInventoryURLs.removeAll()
        liveMetrics.shutdown()
        lifecycle.shutdown()
        scanning = false
        operating = false
    }

    deinit {
        lifecycle.shutdown()
    }

    func applyAppearance() {
        guard let app = NSApp else { return }
        switch appearanceMode {
        case .system: app.appearance = nil
        case .light: app.appearance = NSAppearance(named: .aqua)
        case .dark: app.appearance = NSAppearance(named: .darkAqua)
        }
    }

    var selectedFiles: [IndexedFile] { selected.sorted().compactMap { fileIndex[$0] } }
    var selectedBytes: Int64 {
        selected.reduce(0) { total, id in
            guard let item = fileIndex[id] else { return total }
            return ByteTotals.adding(total, item.allocatedBytes)
        }
    }
    var selectedLogicalBytes: Int64 {
        selected.reduce(0) { total, id in
            guard let item = fileIndex[id] else { return total }
            return ByteTotals.adding(total, item.logicalBytes)
        }
    }
    var eligibleFiles: [IndexedFile] { eligibleCache }
    var sortedEligibleFiles: [IndexedFile] { sortedEligibleCache }
    var homePath: String { homeDirectory }
    var authorizedPromptRootsList: [String] { Array(authorizedInventoryURLs.keys) }
    var measuredBytes: Int64 { cachedMeasuredBytes }
    var logicalBytes: Int64 { cachedLogicalBytes }
    var candidateBytes: Int64 { cachedCandidateBytes }
    var reclaimableAllocatedBytes: Int64 { cachedReclaimableAllocatedBytes }

    /// Synchronizes category aggregates and selection state whenever `scan.files` or scope changes (fixing R8).
    func syncScanAggregates(markStale: Bool = false) {
        applyScanUpdate(scan, markStale: markStale)
    }

    private func applyScanUpdate(_ base: ScanResult, markStale: Bool) {
        var updated = base
        if markStale && updated.finishedAt != nil {
            updated.isStale = true
        }
        updated.rebuildCategoryAggregates()
        scan = updated
        categories = updated.categories
        scanProgress.categories = updated.categories
        let validIDs = Set(eligibleCache.map(\.id))
        selected = selected.intersection(validIDs)
        conclusions.removeAll { !validIDs.contains($0.fileID) }
    }

    func matchesCategory(_ file: IndexedFile, filter: String) -> Bool {
        InventoryQuery.matchesCategory(file, filter: filter)
    }

    func matchesQuery(_ file: IndexedFile, search: String) -> Bool {
        InventoryQuery.matchesQuery(file, search: search)
    }

    private var inventoryQuery: InventoryQuery {
        var filter = InventoryQuery()
        filter.query = query
        filter.category = category
        filter.sizeFilter = sizeFilter
        filter.typeFilter = typeFilter
        filter.statusFilter = statusFilter
        filter.dateFilter = dateFilter
        filter.locationFilter = locationFilter
        filter.sortOrder = sortOrder
        filter.spaceMapFolderPrefix = spaceMapFolderPrefix
        filter.inventoryRoots = preferences.inventoryRoots
        filter.home = homeDirectory
        filter.now = scan.finishedAt ?? scan.startedAt
        return filter
    }

    var filteredSummary: FilteredInventorySummary {
        let filter = inventoryQuery
        if let cached = filteredCache, cached.query == filter { return cached }
        let summary = buildFilteredSummary(from: filter.apply(to: scan.files), query: filter)
        filteredCache = summary
        return summary
    }

    var reviewableFilteredSummary: FilteredInventorySummary {
        let base = filteredSummary
        if category == "eligible" {
            return base
        }
        if let cached = reviewableFilteredCache, cached.query == base.query {
            return cached
        }
        let summary = buildFilteredSummary(from: base.files.filter(\.isReviewable), query: base.query)
        reviewableFilteredCache = summary
        return summary
    }

    private func buildFilteredSummary(from files: [IndexedFile], query: InventoryQuery) -> FilteredInventorySummary {
        var byCategory: [StorageCategory: [IndexedFile]] = [:]
        var allocated: Int64 = 0
        var logical: Int64 = 0
        var hasPartial = false
        var hasReviewable = false
        for file in files {
            byCategory[file.storageCategory, default: []].append(file)
            allocated = ByteTotals.adding(allocated, file.allocatedBytes)
            logical = ByteTotals.adding(logical, file.logicalBytes)
            if !hasPartial && file.isPartial { hasPartial = true }
            if !hasReviewable && file.isReviewable { hasReviewable = true }
        }
        return FilteredInventorySummary(
            query: query,
            files: files,
            byCategory: byCategory,
            allocated: allocated,
            logical: logical,
            hasPartial: hasPartial,
            hasReviewable: hasReviewable
        )
    }

    var filteredFiles: [IndexedFile] { filteredSummary.files }
    var filteredAllocatedBytes: Int64 { filteredSummary.allocated }
    var filteredLogicalBytes: Int64 { filteredSummary.logical }

    func filesForCategory(_ category: StorageCategory) -> [IndexedFile] {
        filteredSummary.byCategory[category] ?? []
    }

    func spaceMap(category: StorageCategory? = nil, folderPrefix: String? = nil, filtered: Bool = false) -> SpaceMapSlice {
        let filter = filtered ? inventoryQuery : nil
        let key = MapKey(category: category, folder: folderPrefix, language: L10n.code, query: filter)
        if let cached = mapCache[key] { return cached }
        let precomputed = filter != nil ? filteredSummary.files : nil
        let slice = SpaceMapBuilder.build(
            from: scan,
            category: category,
            folderPrefix: folderPrefix,
            language: key.language,
            query: filter,
            precomputedFilteredFiles: precomputed
        )
        if mapCache.count >= 8 { mapCache.removeAll(keepingCapacity: true) }
        mapCache[key] = slice
        return slice
    }

    /// Scope changes invalidate all derived data, including parent aggregates and contextual views.
    func invalidateInventory() {
        var empty = ScanResult()
        empty.roots = preferences.roots
        empty.inventoryRoots = preferences.inventoryRoots
        empty.catalogSource = scan.catalogSource
        scan = empty
        categories = empty.categories
        scanProgress = ScanProgress(categories: empty.categories)
        selected.removeAll()
        conclusions.removeAll()
        orphanBuilds.removeAll()
        worktrees.removeAll()
        projectArtifacts.removeAll()
        contextualScanStatus = "pending"
        contextualScanNotes = []
        spaceMapFolderPrefix = nil
    }

    func resetFilters() {
        query = ""
        sizeFilter = "all"
        typeFilter = "all"
        statusFilter = "all"
        dateFilter = "all"
        locationFilter = "all"
        spaceMapFolderPrefix = nil
    }

    func openCategory(_ cat: StorageCategory) {
        resetFilters()
        category = cat.rawValue
        spaceMapFolderPrefix = nil
        cleanMode = .explore
        page = .findings
        revealWindow?()
    }

    func openCleanCandidates() {
        resetFilters()
        category = "all"
        statusFilter = "eligible"
        cleanMode = .candidates
        page = .findings
    }

    func openExploreSpace() {
        resetFilters()
        category = "all"
        statusFilter = "all"
        cleanMode = .explore
        page = .findings
    }

    func openDuplicates() {
        cleanMode = .duplicates
        page = .findings
    }

    func openAdvancedTools(_ tab: MainToolsTab = .projects) {
        tools.activeToolsTab = tab
        cleanMode = .advanced
        page = .findings
    }

    func openApplications() {
        page = .applications
    }

    func openHistory() {
        page = .activity
    }

    func openSettings(expandAdvanced: Bool = false) {
        if expandAdvanced { showAdvancedSettings = true }
        page = .settings
    }

    func savePreferences() throws {
        guard let store else { throw BrisaError.unavailable("Private store unavailable") }
        try store.write("preferences.json", value: preferences)
    }

    func log(_ message: String) {
        activity.insert(ActivityEntry(message), at: 0)
        activity = Array(activity.prefix(100))
        do { try store?.write("activity.json", value: activity) } catch { lastError = error.localizedDescription }
    }

    func fail(_ error: Error) {
        if let error = error as? BrisaError, case .cancelled = error {
            log(L10n.Activity.logCancelledNoChanges)
            return
        }
        lastError = error.localizedDescription
        log(error.localizedDescription)
    }

    func refreshMetrics(forceSnapshots: Bool = false) {
        liveMetrics.refresh(forceSnapshots: forceSnapshots)
    }

    func refreshAgents() {
        lifecycle.agentsTask?.cancel()
        lifecycle.agentsTask = Task.detached(priority: .utility) { [weak self] in
            let result = AgentDiscovery.detect()
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.agents = result
            }
        }
    }

    func completeWelcome() {
        welcomed = true
        defaults.set(true, forKey: "BrisaWelcomed")
        do { try savePreferences() } catch { fail(error) }
    }

    func policy() throws -> SafetyPolicy {
        try SafetyPolicy(roots: preferences.roots, protectedPaths: preferences.protectedPaths, home: homeDirectory)
    }

    func readPolicy() -> ReadAuthorizationPolicy {
        return ReadAuthorizationPolicy(
            home: homeDirectory,
            projectRoots: preferences.inventoryRoots,
            protectedPaths: preferences.protectedPaths,
            allowSystemLocations: true,
            authorizedPromptRoots: Array(authorizedInventoryURLs.keys)
        )
    }

    func startScan() throws {
        guard !scanning, !operating else { throw BrisaError.rejected("Wait for the active task to finish") }
        if !welcomed { completeWelcome() }
        invalidateInventory()
        let home = homeDirectory
        let cleanupRoots = preferences.roots
        let inventoryRoots = preferences.inventoryRoots
        let authorizedPromptRoots = Array(authorizedInventoryURLs.keys)
        let protectedPaths = preferences.protectedPaths
        scanning = true
        contextualScanStatus = "pending"
        selected.removeAll()
        conclusions = []
        cancellation = CancellationFlag()
        categories = CategoryReport.defaultPending()
        scanProgress = ScanProgress(
            currentCategory: nil,
            completedCategories: 0,
            totalCategories: StorageCategory.allCases.count,
            examinedEntries: 0,
            categories: categories
        )
        let flag = cancellation
        scanGeneration = UUID()
        let generation = scanGeneration
        log(L10n.Activity.logScanStarted)
        let coalescer = ScanProgressCoalescer()
        lifecycle.scanTask?.cancel()
        lifecycle.scanTask = Task.detached(priority: .utility) { [weak self] in
            var config = CategoryScanConfiguration(
                home: home,
                cleanupRoots: cleanupRoots,
                protectedPaths: protectedPaths,
                projectRoots: inventoryRoots
            )
            config.authorizedPromptRoots = authorizedPromptRoots
            let result = CategoryDetector.scan(
                configuration: config,
                cancellation: flag,
                onProgress: { [weak self] progress in
                    guard coalescer.shouldEmit(progress) else { return }
                    Task { @MainActor in
                        guard let self, self.scanning, self.scanGeneration == generation else { return }
                        self.scanProgress = progress
                        self.categories = progress.categories
                    }
                }
            )

            let readPol = ReadAuthorizationPolicy(
                home: home,
                projectRoots: inventoryRoots,
                protectedPaths: protectedPaths,
                allowSystemLocations: true,
                authorizedPromptRoots: authorizedPromptRoots
            )
            let contextControl = ScanControl(cancellation: flag, deadline: Date().addingTimeInterval(10))
            let orphans = contextControl.shouldStop ? [] : OrphanBuildDetector.scanAll(home: home, readPolicy: readPol, control: contextControl)
            let devRoots = readPol.projectRoots.filter { !$0.hasSuffix("/Downloads") }
            let projectScan = contextControl.shouldStop ? WorktreeAndProjectScanResult(worktrees: [], projectArtifacts: []) : WorktreeAndProjectDetector.scanAll(
                authorizedRoots: devRoots,
                readPolicy: readPol,
                maxDepth: 4,
                maxVisitedDirectories: 1_500,
                control: contextControl
            )
            let discoveredWorktrees = projectScan.worktrees
            let discoveredArtifacts = projectScan.projectArtifacts

            await MainActor.run { [weak self] in
                guard let self, self.scanGeneration == generation else { return }
                self.lifecycle.scanTask = nil
                var finalResult = result
                if flag.isCancelled {
                    finalResult.cancelled = true
                    finalResult.complete = false
                    let note = L10n.Activity.logScanCancelledNote
                    if !finalResult.errors.contains(note) { finalResult.errors.append(note) }
                }
                self.scan = finalResult
                self.categories = finalResult.categories
                self.contextualScanStatus = flag.isCancelled ? "cancelled" : (contextControl.isPartial ? "partial" : "measured")
                self.contextualScanNotes = contextControl.coverage.reasons
                self.orphanBuilds = orphans
                self.worktrees = discoveredWorktrees
                self.projectArtifacts = discoveredArtifacts
                self.scanProgress = ScanProgress(
                    currentCategory: nil,
                    completedCategories: result.categories.count,
                    totalCategories: StorageCategory.allCases.count,
                    examinedEntries: result.examined,
                    categories: result.categories
                )
                self.scanning = false
                self.refreshMetrics(forceSnapshots: true)
                let measuredCats = result.categories.filter { $0.status == .measured || $0.status == .partial }.count
                self.log(
                    L10n.Activity.logScanFinished(
                        items: result.files.count,
                        measured: measuredCats,
                        total: result.categories.count,
                        complete: result.complete
                    )
                )
            }
        }
    }

    func cancel() { cancellation.cancel(); operationCancellation.cancel() }

    func setSelection(_ ids: Set<String>) throws {
        guard !operating, !scanning, ids.count <= 100, ids.allSatisfy({ fileIndex[$0]?.isReviewable == true }) else {
            throw BrisaError.rejected("Select up to 100 eligible indexed items after analysis")
        }
        selected = ids
    }

    func selectVisible() {
        do {
            try setSelection(Set(filteredFiles.filter(\.isReviewable).prefix(100).map(\.id)))
        } catch {
            fail(error)
        }
    }

    func selectAllEligible(_ limit: Int = 100) {
        do {
            try setSelection(Set(eligibleFiles.prefix(limit).map(\.id)))
        } catch {
            fail(error)
        }
    }

    func clearSelection() {
        selected.removeAll()
    }

    func toggle(_ file: IndexedFile) {
        guard file.isReviewable else { return }
        var next = selected
        if next.contains(file.id) { next.remove(file.id) } else { next.insert(file.id) }
        do { try setSelection(next) } catch { fail(error) }
    }

    func files(in category: StorageCategory) -> [IndexedFile] {
        filesByCategoryCache[category] ?? []
    }

    func eligibleFiles(in category: StorageCategory) -> [IndexedFile] {
        eligibleByCategoryCache[category] ?? []
    }

    func categorySelectionState(_ category: StorageCategory) -> TriStateCheckmark {
        let eligible = eligibleFiles(in: category)
        guard !eligible.isEmpty else { return .unchecked }
        let selectedCount = eligible.filter { selected.contains($0.id) }.count
        if selectedCount == 0 { return .unchecked }
        return selectedCount == eligible.count ? .checked : .mixed
    }

    func toggleCategorySelection(_ category: StorageCategory) {
        let eligible = eligibleFiles(in: category)
        guard !eligible.isEmpty else { return }
        let state = categorySelectionState(category)
        var next = selected
        if state == .checked {
            for item in eligible { next.remove(item.id) }
        } else {
            for item in eligible where next.count < 100 {
                next.insert(item.id)
            }
        }
        do { try setSelection(next) } catch { fail(error) }
    }

    func reloadJournalEntries() {
        journalEntries = (try? journal?.entries()) ?? []
    }

    /// Executes pre-confirmed inventory Trash moves directly (e.g. from the MenuBar plan reviewer)
    /// without opening a focus-stealing NSAlert window.
    func executePreconfirmedTrash(ids: [String]) async -> OperationExecutionReport {
        let targets = ids.compactMap { fileIndex[$0] }.filter(\.isReviewable)
        guard !operating, !scanning, let operations, !targets.isEmpty else {
            return OperationExecutionReport(
                planID: UUID().uuidString,
                domain: .cacheInventory,
                outcome: .rejected,
                mechanism: .trash,
                restorable: false,
                summaryES: "No se pudo ejecutar la selección actual.",
                summaryEN: "Unable to execute current selection."
            )
        }
        do {
            let policy = try policy()
            for file in targets { _ = try policy.revalidate(file) }
            operating = true
            defer { operating = false }
            operationCancellation = CancellationFlag()
            let flag = operationCancellation
            let entries = try await Task.detached(priority: .utility) {
                try operations.moveToTrash(targets, policy: policy, cancellation: flag)
            }.value
            selected.subtract(Set(ids))
            reloadJournalEntries()
            let trashed = entries.filter { $0.status == "trashed" }
            let movedPaths = Set(trashed.map(\.originalPath))
            var updatedScan = scan
            updatedScan.files.removeAll { movedPaths.contains($0.path) }
            applyScanUpdate(updatedScan, markStale: false)
            refreshMetrics()
            let rejected = entries.filter { $0.status == "rejected" || $0.status == "cancelled" }
            let cancelled = flag.isCancelled || entries.contains { $0.status == "cancelled" }
            let outcome = OperationJournalRecorder.resolveBatchOutcome(
                completed: trashed.count,
                rejected: rejected.count,
                failed: 0,
                cancelled: cancelled
            )
            log(L10n.Activity.logTrashFinished(moved: trashed.count, total: targets.count))
            return OperationExecutionReport(
                planID: UUID().uuidString,
                domain: .cacheInventory,
                outcome: outcome,
                mechanism: .trash,
                restorable: !trashed.isEmpty,
                completedItems: trashed.map(\.originalPath),
                rejectedItems: rejected.map(\.originalPath),
                reclaimedBytesEstimate: trashed.reduce(Int64(0)) { $0 + ($1.allocatedBytes ?? $1.size) },
                summaryES: "Trasladados a la Papelera: \(trashed.count)/\(targets.count) elementos.",
                summaryEN: "Moved to Trash: \(trashed.count)/\(targets.count) items.",
                journalEntries: entries
            )
        } catch {
            reloadJournalEntries()
            return OperationExecutionReport(
                planID: UUID().uuidString,
                domain: .cacheInventory,
                outcome: .failed,
                mechanism: .trash,
                restorable: false,
                failedItems: targets.map(\.path),
                summaryES: error.localizedDescription,
                summaryEN: error.localizedDescription
            )
        }
    }

    private func confirm(title: String, detail: String, items: [String], button: String) async -> Bool {
        guard let app = NSApp as NSApplication? else { return false }
        app.activate(ignoringOtherApps: true); revealWindow?()
        let alert = NSAlert(); alert.alertStyle = .warning; alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: L10n.Common.actionCancel); alert.addButton(withTitle: button)
        alert.buttons[0].keyEquivalent = "\r"; alert.buttons[1].keyEquivalent = ""
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 540, height: min(240, max(72, items.count * 42))))
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false; text.isSelectable = true; text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.string = items.joined(separator: "\n\n")
        text.autoresizingMask = [.width]; scroll.documentView = text; scroll.hasVerticalScroller = true
        alert.accessoryView = scroll
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
        if let container = text.textContainer, let manager = text.layoutManager {
            manager.ensureLayout(for: container)
            text.setFrameSize(NSSize(width: scroll.contentSize.width,
                height: max(scroll.contentSize.height, manager.usedRect(for: container).height + text.textContainerInset.height * 2)))
        }
        // A sheet suspends this task instead of blocking the main actor in runModal().
        // Read-only IPC remains available while the user reviews the paths.
        await Task.yield()
        guard let window = app.windows.first(where: { $0.title == "Brisa" && $0.canBecomeMain }) else { return false }
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        return await withCheckedContinuation { continuation in
            var completed = false
            var timeout: Timer?
            alert.beginSheetModal(for: window) { response in
                guard !completed else { return }
                completed = true
                timeout?.invalidate()
                timeout = nil
                continuation.resume(returning: response == .alertSecondButtonReturn)
            }
            let timer = Timer(timeInterval: 90, repeats: false) { _ in
                window.endSheet(alert.window, returnCode: .abort)
            }
            timeout = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func cleanSelection() async throws -> JSONValue {
        guard !operating, !scanning, let operations else { throw BrisaError.rejected("An operation is active or storage unavailable") }
        let files = selectedFiles
        guard !files.isEmpty else { throw BrisaError.invalid("Select files to review first") }
        let policy = try policy()
        for file in files { _ = try policy.revalidate(file) }
        operating = true; defer { operating = false }
        guard await confirm(
            title: L10n.Activity.alertTrashTitle,
            detail: L10n.Activity.alertTrashDetail,
            items: files.map { L10n.Activity.alertTrashItem(allocated: Formatting.bytes($0.allocatedBytes), logical: Formatting.bytes($0.logicalBytes), path: $0.path) },
            button: L10n.Activity.alertTrashButton
        ) else {
            throw BrisaError.cancelled
        }
        operationCancellation = CancellationFlag(); let flag = operationCancellation
        let entries: [JournalEntry]
        do {
            entries = try await Task.detached(priority: .utility) { try operations.moveToTrash(files, policy: policy, cancellation: flag) }.value
        } catch {
            // A journal/result failure may follow a successful filesystem mutation.
            // Never leave an apparently current selectable index in that situation.
            if let entries = try? journal?.entries() { journalEntries = entries }
            invalidateInventory()
            refreshMetrics()
            throw error
        }
        selected.removeAll()
        journalEntries = try journal?.entries() ?? []
        let moved = Set(entries.filter { $0.status == "trashed" }.map(\.originalPath))
        var updatedScan = scan
        updatedScan.files.removeAll { moved.contains($0.path) }
        applyScanUpdate(updatedScan, markStale: false)
        refreshMetrics()
        log(L10n.Activity.logTrashFinished(moved: moved.count, total: files.count))
        if preferences.notifications {
            notify(L10n.Activity.notificationTrashTitle, L10n.Activity.notificationTrashBody(moved: moved.count, total: files.count))
        }
        return try JSONValue.encode(entries)
    }

    func undo(_ id: String) async throws -> JSONValue {
        guard !operating, !scanning, let operations,
              let entry = journalEntries.first(where: { $0.id == id }), entry.status == "trashed" else { throw BrisaError.rejected("Nothing restorable") }
        operating = true; defer { operating = false }
        guard await confirm(
            title: L10n.Activity.alertRestoreTitle,
            detail: L10n.Activity.alertRestoreDetail,
            items: ["\(Formatting.bytes(entry.size)) · \(entry.originalPath)"],
            button: L10n.Activity.alertRestoreButton
        ) else { throw BrisaError.cancelled }
        let result: JournalEntry
        let home = homeDirectory
        let protectedPaths = preferences.protectedPaths
        do {
            result = try await Task.detached(priority: .utility) {
                try operations.restore(id, home: home, protectedPaths: protectedPaths)
            }.value
        } catch {
            if let entries = try? journal?.entries() { journalEntries = entries }
            invalidateInventory()
            refreshMetrics()
            throw error
        }
        journalEntries = try journal?.entries() ?? []
        syncScanAggregates(markStale: true)
        refreshMetrics()
        log(L10n.Activity.logRestoredFromTrash)
        return try JSONValue.encode(result)
    }

    /// Adds a cleanup root (validated by `SafetyPolicy` — only `~/Library/Caches` and `~/Library/Logs` subtrees).
    func addRoot(_ explicitPath: String? = nil) {
        guard !operating, !scanning else { return }
        var chosenPath = explicitPath
        if chosenPath == nil {
            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
            panel.directoryURL = URL(fileURLWithPath: homeDirectory + "/Library/Caches", isDirectory: true)
            panel.message = L10n.Settings.cleanupRootsPanelMessage
            if panel.runModal() == .OK { chosenPath = panel.url?.path }
        }
        guard let path = chosenPath else { return }
        do {
            let canonical = try SafetyPolicy(roots: [path], protectedPaths: preferences.protectedPaths, home: homeDirectory).roots[0]
            if !preferences.roots.contains(canonical) {
                preferences.roots.append(canonical)
                invalidateInventory()
                try savePreferences()
            }
        } catch { fail(error) }
    }

    func removeRoot(_ path: String) {
        guard !operating, !scanning else { return }
        preferences.roots.removeAll { $0 == path }
        invalidateInventory()
        do { try savePreferences() } catch { fail(error) }
    }

    /// Adds a read-only inventory root (validated by `ReadAuthorizationPolicy.validateInventoryRoot` — allows `~/Downloads`, `~/Developer`, etc., while never enabling cleanup on personal documents).
    func addInventoryRoot(_ explicitPath: String? = nil, suggestedPath: String? = nil) {
        guard !operating, !scanning else { return }
        var chosenPath = explicitPath
        var authorizedURL: URL?
        if chosenPath == nil {
            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
            panel.directoryURL = URL(fileURLWithPath: suggestedPath ?? homeDirectory, isDirectory: true)
            panel.message = L10n.Settings.inventoryRootsPanelMessage
            if panel.runModal() == .OK { chosenPath = panel.url?.path; authorizedURL = panel.url }
        }
        guard let path = chosenPath else { return }
        do {
            let canonical = try ReadAuthorizationPolicy.validateInventoryRoot(
                path,
                home: homeDirectory,
                protectedPaths: preferences.protectedPaths
            )
            if !preferences.inventoryRoots.contains(canonical) {
                preferences.inventoryRoots.append(canonical)
                try savePreferences()
            }
            if let authorizedURL {
                authorizedInventoryURLs[canonical]?.stopAccessingSecurityScopedResource()
                _ = authorizedURL.startAccessingSecurityScopedResource()
                authorizedInventoryURLs[canonical] = authorizedURL
            }
            invalidateInventory()
        } catch { fail(error) }
    }

    func removeInventoryRoot(_ path: String) {
        guard !operating, !scanning else { return }
        preferences.inventoryRoots.removeAll { $0 == path }
        authorizedInventoryURLs.removeValue(forKey: path)?.stopAccessingSecurityScopedResource()
        invalidateInventory()
        do { try savePreferences() } catch { fail(error) }
    }

    func addProtection(_ path: String? = nil) throws {
        guard !operating, !scanning else { throw BrisaError.rejected("An operation or scan is active") }
        var path = path
        if path == nil {
            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true
            if panel.runModal() == .OK { path = panel.url?.path }
        }
        guard let path else { return }
        guard path.hasPrefix("/"), !path.contains("\0") else { throw BrisaError.invalid("Absolute path required") }
        let canonical = Paths.normalized(path)
        try SafetyPolicy.rejectSymlinks(canonical)
        if !preferences.protectedPaths.contains(canonical) {
            preferences.protectedPaths.append(canonical)
            try savePreferences()
        }
        guard !scan.files.isEmpty else { return }
        let protectedLower = canonical.lowercased()
        var updated = scan
        var changed = false
        for idx in updated.files.indices where SafetyPolicy.within(updated.files[idx].path.lowercased(), protectedLower) {
            updated.files[idx].eligible = false
            updated.files[idx].selectionAllowed = false
            updated.files[idx].inventoryOnly = true
            updated.files[idx].cleanupEligibility = .lockedProtectedScope
            updated.files[idx].reclaimableBytes = 0
            updated.files[idx].reason = "user_protected"
            updated.files[idx].explanationES = "Protegido por el usuario; nunca se seleccionará para limpieza."
            updated.files[idx].explanationEN = "Protected by user; it will never be selected for cleanup."
            changed = true
        }
        if changed {
            applyScanUpdate(updated, markStale: false)
        }
    }

    func removeProtection(_ path: String) async throws {
        guard !operating, !scanning else { throw BrisaError.rejected("An operation is active") }
        guard preferences.protectedPaths.contains(path) else { throw BrisaError.invalid("Not a user protection") }
        operating = true; defer { operating = false }
        guard await confirm(
            title: L10n.Activity.alertRemoveProtectionTitle,
            detail: L10n.Activity.alertRemoveProtectionDetail,
            items: [path],
            button: L10n.Common.actionRemove
        ) else { throw BrisaError.cancelled }
        preferences.protectedPaths.removeAll { $0 == path }
        invalidateInventory()
        try savePreferences()
    }

    func notificationPermission() async {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            preferences.notifications = allowed
            notificationAuthorization = allowed
            try savePreferences()
        } catch { fail(error) }
    }

    private func notify(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent(); content.title = title; content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func loadApplications(force: Bool = false) {
        guard !loadingApplications else { return }
        guard force || !hasLoadedApplications || applicationsScanIncomplete else { return }
        loadingApplications = true
        let home = homeDirectory
        lifecycle.applicationsTask?.cancel()
        lifecycle.applicationsTask = Task.detached(priority: .utility) { [weak self] in
            let paths = ["/Applications", home + "/Applications"]
            let discovered = ApplicationDiscovery.discover(
                in: paths,
                control: ScanControl(deadline: Date().addingTimeInterval(5))
            )
            guard !Task.isCancelled else { return }
            let apps = discovered.urls
                .map { ApplicationItem(url: $0) }
                .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            var remnants: [String: [String]] = [:]
            remnants.reserveCapacity(apps.count)
            for app in apps {
                remnants[app.id] = Self.computeApplicationRemnants(bundleID: app.bundleID, home: home)
            }
            guard !Task.isCancelled else { return }
            let finalRemnants = remnants
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.applications = apps
                self.applicationRemnantsByID = finalRemnants
                self.applicationsScanIncomplete = !discovered.complete
                self.hasLoadedApplications = true
                self.loadingApplications = false
                self.lifecycle.applicationsTask = nil
            }
        }
    }

    func applicationRemnants(_ app: ApplicationItem) -> [String] {
        applicationRemnantsByID[app.id] ?? Self.computeApplicationRemnants(bundleID: app.bundleID, home: homeDirectory)
    }

    nonisolated private static func computeApplicationRemnants(bundleID: String?, home: String) -> [String] {
        guard let id = bundleID, id.contains("."), !id.contains("/"), !id.contains("..") else { return [] }
        return ["Library/Caches/" + id, "Library/Logs/" + id, "Library/Preferences/" + id + ".plist", "Library/Application Support/" + id]
            .map { home + "/" + $0 }
            .filter { FileManager.default.fileExists(atPath: $0) }
    }

    func handle(_ request: IPCRequest) async throws -> JSONValue {
        try request.validate()
        if !request.command.hasPrefix("mcp.") { _ = try CLIOptions([request.command] + request.arguments) }
        switch request.command {
        case "status", "mcp.summary":
            _ = await liveMetrics.sample()
            return .object([
                "appVersion": .string("0.1.0"),
                "metrics": try metrics.map(JSONValue.encode) ?? .null,
                "scanning": .bool(scanning),
                "operating": .bool(operating),
                "scanComplete": .bool(scan.complete),
                "scanCancelled": .bool(scan.cancelled),
                "scanIsStale": .bool(scan.isStale),
                "scanFinishedAt": try scan.finishedAt.map(JSONValue.encode) ?? .null,
                "catalogSource": .string(scan.catalogSource),
                "files": .number(Double(scan.files.count)),
                "measuredAllocatedBytes": .number(Double(measuredBytes)),
                "logicalBytes": .number(Double(logicalBytes)),
                "reclaimableAllocatedBytes": .number(Double(reclaimableAllocatedBytes)),
                "candidateLogicalBytes": .number(Double(candidateBytes)),
                "examinedEntries": .number(Double(scan.examined)),
                "skippedEntries": .number(Double(scan.skipped)),
                "selected": .number(Double(selected.count)),
                "orphanBuildsCount": .number(Double(orphanBuilds.count)),
                "worktreesCount": .number(Double(worktrees.count)),
                "projectArtifactsCount": .number(Double(projectArtifacts.count)),
                "contextualScanStatus": .string(contextualScanStatus),
                "contextualScanNotes": try JSONValue.encode(contextualScanNotes),
                "categories": try JSONValue.encode(categories),
                "scanProgress": try JSONValue.encode(scanProgress),
                "scanErrors": try JSONValue.encode(scan.errors),
                "roots": try JSONValue.encode(preferences.roots),
                "inventoryRoots": try JSONValue.encode(preferences.inventoryRoots),
                "lastError": lastError.map(JSONValue.string) ?? .null
            ])
        case "categories":
            var filtered = categories
            if request.arguments.count == 2, request.arguments[0] == "--category" {
                let target = request.arguments[1]
                filtered = categories.filter { $0.category.rawValue == target }
            }
            return .object([
                "catalogSource": .string(scan.catalogSource),
                "scanning": .bool(scanning),
                "scanComplete": .bool(scan.complete),
                "scanIsStale": .bool(scan.isStale),
                "measuredAllocatedBytes": .number(Double(measuredBytes)),
                "logicalBytes": .number(Double(logicalBytes)),
                "reclaimableAllocatedBytes": .number(Double(reclaimableAllocatedBytes)),
                "categories": try JSONValue.encode(filtered)
            ])
        case "orphans":
            return try JSONValue.encode(orphanBuilds)
        case "worktrees", "mcp.gitStatus":
            return .object([
                "available": .bool(contextualScanStatus != "pending"),
                "status": .string(contextualScanStatus),
                "coverageNotes": try JSONValue.encode(contextualScanNotes),
                "mode": .string("inventory_only"),
                "deletionEnabled": .bool(false),
                "worktrees": try JSONValue.encode(worktrees),
                "projectArtifacts": try JSONValue.encode(projectArtifacts)
            ])
        case "diagnostics":
            let diag = await Task.detached(priority: .utility) {
                SystemDiagnostics.collectAll(includeLocalSnapshots: true)
            }.value
            return try JSONValue.encode(diag)
        case "spacemap":
            let slice = spaceMap()
            return try JSONValue.encode(slice)
        case "agents", "mcp.agents": return try JSONValue.encode(agents)
        case "analyse": try startScan(); return .object(["started": .bool(true)])
        case "findings", "mcp.large", "mcp.list":
            try CLIOptions.validateFindingsArguments(request.arguments)
            let snapshotFiles = scan.files
            let scanComplete = scan.complete
            let scanIsStale = scan.isStale
            let catalogSource = scan.catalogSource
            let isLarge = request.command == "mcp.large"
            let arguments = request.arguments
            return await Task.detached(priority: .utility) {
                var searchFilters: [String] = []
                var categoryFilters: [String] = []
                var limit = isLarge ? 30 : 100
                var i = 0
                while i + 1 < arguments.count {
                    let value = arguments[i + 1]
                    switch arguments[i] {
                    case "--search": searchFilters.append(value)
                    case "--category": categoryFilters.append(value)
                    case "--limit": limit = Int(value) ?? 100
                    default: break
                    }
                    i += 2
                }

                var query = InventoryQuery()
                if searchFilters.count == 1 { query.query = searchFilters[0] }
                if categoryFilters.count == 1 { query.category = categoryFilters[0] }
                var filtered = (searchFilters.count <= 1 && categoryFilters.count <= 1)
                    ? query.filterUnsorted(snapshotFiles)
                    : snapshotFiles
                if searchFilters.count > 1 {
                    for term in searchFilters {
                        filtered = filtered.filter { InventoryQuery.matchesQuery($0, search: term) }
                    }
                }
                if categoryFilters.count > 1 {
                    for cat in categoryFilters {
                        filtered = filtered.filter { InventoryQuery.matchesCategory($0, filter: cat) }
                    }
                }
                if isLarge {
                    // Consistent sorting by allocatedBytes descending (never substituting logicalBytes when allocatedBytes == 0)
                    filtered.sort {
                        if $0.allocatedBytes != $1.allocatedBytes { return $0.allocatedBytes > $1.allocatedBytes }
                        if $0.logicalBytes != $1.logicalBytes { return $0.logicalBytes > $1.logicalBytes }
                        return $0.path < $1.path
                    }
                }
                let encodedItems = filtered.prefix(limit).map { $0.toJSONValue() }
                return .object([
                    "items": .array(encodedItems),
                    "total": .number(Double(filtered.count)),
                    "truncated": .bool(filtered.count > limit),
                    "scanComplete": .bool(scanComplete),
                    "scanIsStale": .bool(scanIsStale),
                    "catalogSource": .string(catalogSource)
                ])
            }.value
        case "select": try setSelection(request.arguments == ["none"] ? [] : Set(request.arguments)); return try JSONValue.encode(selectedFiles)
        case "clean", "free": return try await cleanSelection()
        case "journal": journalEntries = try journal?.entries() ?? []; return try JSONValue.encode(journalEntries)
        case "undo": return try await undo(request.arguments[0])
        case "protect": try addProtection(request.arguments[0]); return try JSONValue.encode(preferences.protectedPaths)
        case "unprotect": try await removeProtection(request.arguments[0]); return try JSONValue.encode(preferences.protectedPaths)
        case "protected": return try JSONValue.encode(preferences.protectedPaths)
        case "keep-process":
            guard let pid = Int32(request.arguments[0]), pid > 1, try ProcessInspector.list().contains(where: { $0.id == pid }) else { throw BrisaError.invalid("Not a current user process") }
            if !preferences.keptProcesses.contains(pid) { preferences.keptProcesses.append(pid); try savePreferences() }
            return .object(["keptPID": .number(Double(pid)), "terminationEnabled": .bool(false)])
        case "routine": return .object(["enabled": .bool(false), "available": .bool(false), "reason": .string("Automatic cleanup is not implemented")])
        case "update": return .object(["available": .bool(false), "reason": .string("No signed update feed configured. Use owner-signed releases.")])
        case "alerts":
            if request.arguments[0] == "on" { revealWindow?(); page = .settings; await notificationPermission() }
            if request.arguments[0] == "off" { preferences.notifications = false; try savePreferences() }
            return .object(["enabled": .bool(preferences.notifications)])
        case "setup", "settings", "open": page = request.command == "open" ? .overview : .settings; revealWindow?(); return .bool(true)
        case "quit":
            guard !hasActiveWork else { throw BrisaError.rejected("An operation is active") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                // Delivering the CLI response yields to other requests. Recheck before stopping services.
                guard !self.hasActiveWork else {
                    self.lastError = L10n.Activity.quitConfirmActiveTask
                    return
                }
                self.shutdown()
                (NSApp as NSApplication?)?.terminate(nil)
            }
            return .bool(true)
        case "mcp.info", "mcp.openFiles", "mcp.git":
            guard request.arguments.count == 1, let file = fileIndex[request.arguments[0]] else { throw BrisaError.invalid("Indexed file ID required") }
            let readPol = readPolicy()
            guard readPol.isMetadataAllowed(file.path) else { throw BrisaError.rejected("Path not authorized for metadata inspection") }
            if request.command == "mcp.info" {
                let allFiles = scan.files
                return try await Task.detached(priority: .utility) {
                    let claimedPaths = Set(allFiles.map(\.path))
                    let updated = try InventoryMetadata.refresh(file, readPolicy: readPol, claimedPaths: claimedPaths)
                    return try JSONValue.encode(updated)
                }.value
            }
            if request.command == "mcp.openFiles" {
                return try await Task.detached(priority: .utility) { try JSONValue.encode(ProcessInspector.openPIDs(file.path)) }.value
            }
            throw BrisaError.unavailable("Use git_status for read-only worktree and project artifact inventory")
        case "mcp.processes": return try await Task.detached(priority: .utility) { try JSONValue.encode(ProcessInspector.list()) }.value
        case "mcp.submit":
            guard request.arguments.count == 1, let data = request.arguments[0].data(using: .utf8) else { throw BrisaError.invalid("Structured conclusions required") }
            let result = try JSONDecoder().decode([AgentConclusion].self, from: data)
            let valid = try AgentValidator.validate(result, index: scan.files)
            for conclusion in valid {
                guard let file = fileIndex[conclusion.fileID] else { throw BrisaError.rejected("Stale finding") }
                _ = try policy().revalidate(file)
            }
            conclusions = valid; log(L10n.Activity.logConclusionsDataOnly)
            return .object(["accepted": .number(Double(valid.count)), "operationsExecuted": .number(0)])
        default: throw BrisaError.invalid("Unknown command")
        }
    }
}
