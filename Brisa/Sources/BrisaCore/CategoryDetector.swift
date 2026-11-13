import Foundation
import Darwin

public typealias CategoryScanConfiguration = InventoryScanConfiguration

public struct InventoryScanConfiguration: Sendable {
    public var home: String
    public var roots: [String]
    public var protectedPaths: [String]
    public var projectRoots: [String]
    public var authorizedPromptRoots: [String] = []
    public var allowSystemLocations: Bool
    public var systemRootPrefix: String?
    public var includeExtendedRules: Bool
    public var maxEntries: Int
    public var timeLimit: TimeInterval
    public var maxRecursiveDepth: Int
    public var catalogBundle: Bundle?
    public var catalogURL: URL?
    public var environmentSnapshot: SystemEnvironmentSnapshot?
    public var now: Date

    public init(
        home: String = NSHomeDirectory(),
        roots: [String] = [],
        protectedPaths: [String] = [],
        projectRoots: [String] = [],
        allowSystemLocations: Bool = true,
        systemRootPrefix: String? = nil,
        includeExtendedRules: Bool = true,
        maxEntries: Int = 250_000,
        timeLimit: TimeInterval = 35,
        maxRecursiveDepth: Int = 4,
        catalogBundle: Bundle? = nil,
        catalogURL: URL? = nil,
        environmentSnapshot: SystemEnvironmentSnapshot? = nil,
        now: Date = Date()
    ) {
        self.home = Paths.normalized(home)
        self.roots = roots.map(Paths.normalized)
        self.protectedPaths = protectedPaths.map(Paths.normalized)
        self.projectRoots = projectRoots.map(Paths.normalized)
        self.allowSystemLocations = allowSystemLocations
        self.systemRootPrefix = systemRootPrefix.map(Paths.normalized)
        self.includeExtendedRules = includeExtendedRules
        self.maxEntries = maxEntries
        self.timeLimit = timeLimit
        self.maxRecursiveDepth = maxRecursiveDepth
        self.catalogBundle = catalogBundle
        self.catalogURL = catalogURL
        self.environmentSnapshot = environmentSnapshot
        self.now = now
    }

    public init(
        home: String = NSHomeDirectory(),
        cleanupRoots: [String],
        protectedPaths: [String] = [],
        projectRoots: [String] = [],
        includeSystemRoots: Bool = true,
        includeExtendedRules: Bool = true
    ) {
        self.init(
            home: home,
            roots: cleanupRoots,
            protectedPaths: protectedPaths,
            projectRoots: projectRoots,
            allowSystemLocations: includeSystemRoots,
            includeExtendedRules: includeExtendedRules
        )
    }
}

public enum CategoryDetector {
    public static func scan(
        configuration: InventoryScanConfiguration,
        cancellation: CancellationFlag = CancellationFlag(),
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil
    ) -> ScanResult {
        var result = ScanResult()
        result.roots = configuration.roots
        result.inventoryRoots = configuration.projectRoots
        let started = Date()
        let deadline = started.addingTimeInterval(max(0, configuration.timeLimit))
        // Discovery must leave room to measure what it finds. Reaching either phase's
        // cap remains explicit partial coverage; it must not result in an empty inventory.
        let discoveryDeadline = started.addingTimeInterval(max(0, configuration.timeLimit) * 0.45)
        let discoveryEntryLimit = max(1, configuration.maxEntries / 2)
        var protectionDiscoveryIncomplete = false

        let loadedCatalog: LoadedCatalog
        do {
            loadedCatalog = try CatalogLoader.load(from: configuration.catalogBundle, url: configuration.catalogURL)
        } catch {
            result.errors.append("Catalog load failed: \(error.localizedDescription)")
            result.categories = CategoryReport.defaultPending().map { rep in
                var copy = rep
                copy.status = .partial
                copy.errors = [error.localizedDescription]
                copy.statusNoteES = "Error al cargar el catálogo"
                copy.statusNoteEN = "Catalog load failed"
                return copy
            }
            result.finishedAt = Date()
            return result
        }

        let catalog = loadedCatalog.catalog
        result.catalogSource = loadedCatalog.sourceKind
        let definedCounts = catalog.ruleCountsByCategory
        var reportsByCategory: [StorageCategory: CategoryReport] = Dictionary(
            uniqueKeysWithValues: StorageCategory.allCases.map { cat in
                (cat, CategoryReport(
                    category: cat,
                    status: .pending,
                    definedRuleCount: definedCounts[cat] ?? 0,
                    statusNoteES: "Pendiente de análisis",
                    statusNoteEN: "Pending analysis"
                ))
            }
        )

        let readPolicy = ReadAuthorizationPolicy(
            home: configuration.home,
            projectRoots: configuration.roots + configuration.projectRoots,
            protectedPaths: configuration.protectedPaths,
            allowSystemLocations: configuration.allowSystemLocations,
            systemRootPrefix: configuration.systemRootPrefix,
            authorizedPromptRoots: configuration.authorizedPromptRoots
        )

        let safetyPolicy = try? SafetyPolicy(
            roots: configuration.roots,
            protectedPaths: configuration.protectedPaths,
            home: configuration.home
        )

        let snapshot = configuration.environmentSnapshot ?? SystemEnvironmentSnapshot.capture(
            home: configuration.home,
            includeSystemApps: configuration.allowSystemLocations,
            control: ScanControl(cancellation: cancellation, deadline: discoveryDeadline)
        )

        var claimedPaths = Set<String>()
        var seenInodes = Set<InodeKey>()
        var neverTouchedPaths = Set<String>()

        // 1. Expand direct Never Touched rules so no category rule or root pass ever touches them
        for rule in catalog.neverTouchedRules {
            if cancellation.isCancelled || Date() >= deadline || result.examined >= configuration.maxEntries {
                break
            }
            for pat in rule.patterns {
                if !pat.contains("*") && !pat.contains("?") && !pat.contains("[") {
                    if pat.hasPrefix("~/") {
                        neverTouchedPaths.insert(Paths.normalized(readPolicy.home + String(pat.dropFirst(1))))
                    } else if pat.hasPrefix("/") {
                        neverTouchedPaths.insert(Paths.normalized((readPolicy.systemRootPrefix ?? "") + pat))
                    }
                }
            }
            let hasWildcard = rule.patterns.contains { $0.contains("*") || $0.contains("?") || $0.contains("[") }
            if !hasWildcard {
                continue
            }
            let remainingForNever = min(200, max(0, configuration.maxEntries - result.examined))
            guard remainingForNever > 0 else { break }
            var dummyStats = PatternMatchStats()
            dummyStats.deadline = discoveryDeadline
            let matches = PatternMatcher.expand(
                rule: rule,
                readPolicy: readPolicy,
                claimedPaths: [],
                neverTouchedPaths: [],
                cancellation: cancellation,
                maxRecursiveDepth: 1,
                maxEntriesPerRule: remainingForNever,
                stats: &dummyStats
            )
            result.examined += dummyStats.examinedEntries
            protectionDiscoveryIncomplete = protectionDiscoveryIncomplete || dummyStats.hitBudgetOrCancelled
            for m in matches {
                neverTouchedPaths.insert(m.path)
            }
        }

        // 2. Phase 1: Expand all active catalog rules ordered globally by specificity so specific rules
        //    and listOnly/neverTicked/never rules claim paths before generic catch-all rules or root passes.
        let activeRules = catalog.allRules.filter { rule in
            guard rule.storageCategory != nil else { return false }
            return configuration.includeExtendedRules || rule.isPrimaryCategoryGroup
        }
        let sortedRules = PatternMatcher.sortBySpecificity(activeRules)

        var candidatesByCategory: [StorageCategory: [MatchedCandidate]] = [:]
        var statsByCategory: [StorageCategory: PatternMatchStats] = [:]
        var matchedRuleIDsByCategory: [StorageCategory: Set<String>] = [:]

        for rule in sortedRules {
            guard let category = rule.storageCategory else { continue }
            let remainingBudget = discoveryEntryLimit - result.examined
            if cancellation.isCancelled || Date() >= discoveryDeadline || remainingBudget <= 0 {
                result.cancelled = cancellation.isCancelled
                var st = statsByCategory[category] ?? PatternMatchStats()
                st.hitBudgetOrCancelled = true
                statsByCategory[category] = st
                continue
            }

            var ruleStats = PatternMatchStats()
            ruleStats.deadline = discoveryDeadline
            var matches = PatternMatcher.expand(
                rule: rule,
                readPolicy: readPolicy,
                claimedPaths: claimedPaths,
                neverTouchedPaths: neverTouchedPaths,
                cancellation: cancellation,
                maxRecursiveDepth: configuration.maxRecursiveDepth,
                maxEntriesPerRule: min(6_000, remainingBudget),
                stats: &ruleStats
            )

            // Filter app leftovers against installed applications (without arbitrary truncation)
            if category == .appLeftovers && (rule.id == "app-support-leftovers" || rule.id == "container-leftovers" || rule.id == "preferences-leftovers") {
                matches = matches.filter { cand in
                    SelectionPolicy.isPlausibleUninstalledLeftover(path: cand.path, ruleID: rule.id, snapshot: snapshot)
                }
            }

            var catStats = statsByCategory[category] ?? PatternMatchStats()
            catStats.existingBaseRoots += ruleStats.existingBaseRoots
            catStats.accessDeniedCount += ruleStats.accessDeniedCount
            catStats.examinedEntries += ruleStats.examinedEntries
            catStats.hitBudgetOrCancelled = catStats.hitBudgetOrCancelled || ruleStats.hitBudgetOrCancelled
            for err in ruleStats.errors where catStats.errors.count < 10 {
                catStats.errors.append(err)
            }
            statsByCategory[category] = catStats
            result.examined += ruleStats.examinedEntries

            if !matches.isEmpty {
                matchedRuleIDsByCategory[category, default: []].insert(rule.id)
                for m in matches {
                    claimedPaths.insert(m.path)
                    candidatesByCategory[category, default: []].append(m)
                }
            }
        }

        // 3. Fallback root discovery for any remaining unclaimed individual regular files (.cache, .tmp, .log)
        //    directly inside authorized SafetyPolicy roots. Evaluates through the exact same SelectionPolicy
        //    and respects neverTouchedPaths and claimedPaths.
        let fallbackCacheRule = CatalogRule(
            id: "user-caches",
            sourceGroup: "apps",
            isPrimaryCategoryGroup: true,
            displayCategory: StorageCategory.appCaches.rawValue,
            titleES: "Caché individual",
            titleEN: "Individual cache",
            explanationES: "Archivo de caché individual en raíz autorizada de limpieza.",
            explanationEN: "Individual cache file in authorized cleanup root.",
            regenBehavior: "rebuilt",
            patterns: ["~/Library/Caches/*"],
            tier: .regenerable,
            listOnly: false,
            neverTicked: false
        )
        let fallbackLogRule = CatalogRule(
            id: "user-logs",
            sourceGroup: "logs",
            isPrimaryCategoryGroup: true,
            displayCategory: StorageCategory.logsAndCrashes.rawValue,
            titleES: "Registro individual",
            titleEN: "Individual log",
            explanationES: "Archivo de registro individual en raíz autorizada de limpieza.",
            explanationEN: "Individual log file in authorized cleanup root.",
            regenBehavior: "gone",
            patterns: ["~/Library/Logs/*.log"],
            tier: .regenerable,
            listOnly: false,
            neverTicked: false
        )

        if let safetyPolicy, !safetyPolicy.roots.isEmpty {
            outerRoot: for root in safetyPolicy.roots {
                guard let dir = Paths.openDirectory(root) else { continue }
                defer { closedir(dir) }
                let isRootSlash = root == "/"
                while let entry = readdir(dir) {
                    if cancellation.isCancelled || Date() >= discoveryDeadline || result.examined >= discoveryEntryLimit {
                        result.cancelled = cancellation.isCancelled
                        for cat in [StorageCategory.appCaches, .logsAndCrashes] {
                            var st = statsByCategory[cat] ?? PatternMatchStats()
                            st.hitBudgetOrCancelled = true
                            statsByCategory[cat] = st
                        }
                        break outerRoot
                    }
                    let name = withUnsafePointer(to: entry.pointee.d_name) {
                        $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                            String(cString: $0)
                        }
                    }
                    if name == "." || name == ".." || name.hasPrefix(".") { continue }
                    result.examined += 1
                    let candidatePath = isRootSlash ? "/\(name)" : "\(root)/\(name)"
                    if Paths.containsAncestor(of: candidatePath, in: neverTouchedPaths) {
                        result.skipped += 1
                        continue
                    }
                    if readPolicy.requiresUnauthedTCCPrompt(candidatePath) || safetyPolicy.exclusion(candidatePath) != nil {
                        result.skipped += 1
                        continue
                    }
                    var st = stat()
                    guard lstat(candidatePath, &st) == 0 else {
                        result.skipped += 1
                        continue
                    }
                    let mode = st.st_mode & S_IFMT
                    if mode == S_IFLNK {
                        result.skipped += 1
                        continue
                    }
                    guard mode == S_IFREG else { continue }
                    // Skip if already claimed by a catalog rule
                    if Paths.containsAncestor(of: candidatePath, in: claimedPaths) {
                        continue
                    }
                    guard let dot = name.lastIndex(of: ".") else { continue }
                    let ext = name[name.index(after: dot)...].lowercased()
                    guard ext == "cache" || ext == "tmp" || ext == "log" else { continue }
                    let targetCat: StorageCategory = (ext == "log") ? .logsAndCrashes : .appCaches
                    let ruleToUse = (ext == "log") ? fallbackLogRule : fallbackCacheRule
                    claimedPaths.insert(candidatePath)
                    matchedRuleIDsByCategory[targetCat, default: []].insert(ruleToUse.id)
                    candidatesByCategory[targetCat, default: []].append(
                        MatchedCandidate(path: candidatePath, rule: ruleToUse, matchedPattern: root, isDirectory: false)
                    )
                    var catStat = statsByCategory[targetCat] ?? PatternMatchStats()
                    catStat.existingBaseRoots += 1
                    statsByCategory[targetCat] = catStat
                }
            }
        }

        // 4. Phase 2: Measure and evaluate category by category in priority order, emitting progress
        let allCategories = StorageCategory.allCases
        let perCategoryBudget = max(1, min(configuration.maxEntries, max(80_000, configuration.maxEntries / 3)))
        let inspectablePaths = candidatesByCategory.values.flatMap { $0 }.filter {
            !$0.isDirectory && !$0.rule.listOnly && !$0.rule.neverTicked && $0.rule.tier != .never
                && !$0.rule.hasUnverifiedCondition && !$0.rule.requiresTypedAdapter
        }.map(\.path)
        let openFiles = ScanOpenFileInspector(paths: inspectablePaths,
            control: ScanControl(cancellation: cancellation, deadline: deadline))

        for (index, category) in allCategories.enumerated() {
            if var rep = reportsByCategory[category] {
                rep.status = .scanning
                rep.statusNoteES = "Analizando…"
                rep.statusNoteEN = "Scanning…"
                reportsByCategory[category] = rep
            }
            onProgress?(ScanProgress(
                currentCategory: category,
                completedCategories: index,
                totalCategories: allCategories.count,
                examinedEntries: result.examined,
                categories: allCategories.compactMap { reportsByCategory[$0] }
            ))

            var categoryFiles: [IndexedFile] = []
            var catStats = statsByCategory[category] ?? PatternMatchStats()

            let candidates = candidatesByCategory[category] ?? []
            var hadPartialItem = false
            var partialReasons: [String] = []
            var categoryExamined = 0

            for candidate in candidates {
                let remainingGlobal = configuration.maxEntries - result.examined
                if cancellation.isCancelled || Date() >= deadline || remainingGlobal <= 0 {
                    result.cancelled = cancellation.isCancelled
                    catStats.hitBudgetOrCancelled = true
                    break
                }
                if categoryExamined >= perCategoryBudget {
                    catStats.hitBudgetOrCancelled = true
                    break
                }

                var examinedDelta = 0
                let itemMax = min(2_000, remainingGlobal, perCategoryBudget - categoryExamined)
                let measured = StorageMeasurement.measure(
                    path: candidate.path,
                    category: category,
                    readPolicy: readPolicy,
                    claimedPaths: claimedPaths,
                    neverTouchedPaths: neverTouchedPaths,
                    seenInodes: &seenInodes,
                    cancellation: cancellation,
                    maxEntriesPerItem: itemMax,
                    examinedCounter: &examinedDelta,
                    deadline: deadline
                )
                // Empty/excluded directories may return nil after visiting entries.
                // Those reads still consume the shared budget.
                result.examined += examinedDelta
                categoryExamined += examinedDelta
                guard let measurement = measured else {
                    result.skipped += 1
                    continue
                }
                if measurement.isPartial {
                    hadPartialItem = true
                    if let pReason = measurement.partialReason, !partialReasons.contains(pReason) {
                        partialReasons.append(pReason)
                    }
                }
                catStats.accessDeniedCount += measurement.accessDeniedCount

                let evaluation = SelectionPolicy.evaluate(
                    rule: candidate.rule,
                    measurement: measurement,
                    safetyPolicy: safetyPolicy,
                    snapshot: snapshot,
                    now: configuration.now,
                    openFileCheck: openFiles.openPIDs,
                    forceInventoryOnly: protectionDiscoveryIncomplete
                )

                var conds = evaluation.conditionsSummary
                if measurement.isPartial {
                    conds.append("measurement:partial(\(measurement.partialReason ?? "truncated"))")
                }

                var expES = candidate.rule.explanationES
                var expEN = candidate.rule.explanationEN
                var itemInventoryOnly = evaluation.inventoryOnly
                var itemSelectionAllowed = evaluation.selectionAllowed
                var itemEligible = evaluation.eligible
                var itemReclaimable = evaluation.reclaimableBytes
                var itemEligibility = evaluation.cleanupEligibility
                var itemReason = evaluation.reason

                if measurement.isDirectory && (candidate.rule.id == "xcode-derived-data" || candidate.rule.id == "xcodebuildmcp-orphans") {
                    let leafLower = URL(fileURLWithPath: measurement.path).lastPathComponent.lowercased()
                    if leafLower != "modulecache.noindex" && leafLower != "symbolcache.noindex" {
                        let orphanAssessment = OrphanBuildDetector.inspect(
                            buildDirectory: measurement.path,
                            readPolicy: readPolicy,
                            now: configuration.now,
                            premeasuredAllocated: measurement.allocatedBytes,
                            premeasuredLogical: measurement.logicalBytes,
                            control: ScanControl(cancellation: cancellation, deadline: deadline)
                        )
                        conds.append("orphan_status:\(orphanAssessment.status.rawValue)")
                        if !orphanAssessment.recordedWorkspacePaths.isEmpty {
                            conds.append("workspace_ref:\(orphanAssessment.recordedWorkspacePaths.joined(separator: "|"))")
                        }
                        expES = "\(expES) · \(orphanAssessment.explanationES)"
                        expEN = "\(expEN) · \(orphanAssessment.explanationEN)"
                        // DerivedData / XcodeBuildMCP workspace builds inspected via OrphanBuildDetector stay in inventory mode
                        itemInventoryOnly = true
                        itemSelectionAllowed = false
                        itemEligible = false
                        itemReclaimable = 0
                        itemEligibility = .inventoryOnly
                        itemReason = "Inventory only (OrphanBuildDetector: \(orphanAssessment.status.rawValue))"
                    }
                }

                let leafName = URL(fileURLWithPath: candidate.path).lastPathComponent
                let displayTitleES = "\(candidate.rule.titleES) · \(leafName)"
                let displayTitleEN = "\(candidate.rule.titleEN) · \(leafName)"

                let itemRoot = safetyPolicy?.roots.first(where: { SafetyPolicy.within(measurement.path, $0) }) ?? readPolicy.home
                let indexed = IndexedFile(
                    id: "\(measurement.identity.device):\(measurement.identity.inode):\(measurement.identity.modified):\(measurement.identity.changed)",
                    path: measurement.path,
                    root: itemRoot,
                    identity: measurement.identity,
                    allocatedBytes: measurement.allocatedBytes,
                    category: category.legacyCategory,
                    modifiedAt: measurement.modifiedAt,
                    eligible: itemEligible,
                    reason: itemReason,
                    confidence: evaluation.confidence,
                    storageCategory: category,
                    titleES: displayTitleES,
                    titleEN: displayTitleEN,
                    ruleID: candidate.rule.id,
                    sourceGroup: candidate.rule.sourceGroup,
                    isDirectory: measurement.isDirectory,
                    childCount: measurement.childCount,
                    logicalBytes: measurement.logicalBytes,
                    virtualCapacityBytes: measurement.virtualCapacityBytes,
                    reclaimableBytes: itemReclaimable,
                    dataKind: candidate.rule.tier,
                    inventoryOnly: itemInventoryOnly,
                    selectionAllowed: itemSelectionAllowed,
                    cleanupEligibility: itemEligibility,
                    usageState: evaluation.usageState,
                    dateKind: measurement.dateKind,
                    explanationES: expES,
                    explanationEN: expEN,
                    conditionsSummary: conds,
                    isPartial: measurement.isPartial,
                    partialReason: measurement.partialReason,
                    provenance: candidate.rule.provenance,
                    upstreamProvenance: candidate.rule.upstreamProvenance,
                    regenBehavior: candidate.rule.regenBehavior
                )
                categoryFiles.append(indexed)
            }

            categoryFiles.sort {
                if $0.allocatedBytes != $1.allocatedBytes { return $0.allocatedBytes > $1.allocatedBytes }
                if $0.logicalBytes != $1.logicalBytes { return $0.logicalBytes > $1.logicalBytes }
                return $0.path < $1.path
            }
            result.files.append(contentsOf: categoryFiles)

            for err in catStats.errors where result.errors.count < 30 {
                if !result.errors.contains(err) {
                    result.errors.append(err)
                }
            }

            // Build CategoryReport with explicit status for unmeasured/empty/notInstalled/noAccess/partial
            var totalAllocated: Int64 = 0
            var totalLogical: Int64 = 0
            var totalReclaimable: Int64 = 0
            var eligibleCount = 0
            var byteOverflow = false
            var hasVirtualDisk = false
            var virtualTotalAcc: Int64 = 0
            var virtualOverflow = false
            for file in categoryFiles {
                let allocSum = totalAllocated.addingReportingOverflow(file.allocatedBytes)
                totalAllocated = allocSum.overflow ? Int64.max : allocSum.partialValue
                let logSum = totalLogical.addingReportingOverflow(file.logicalBytes)
                totalLogical = logSum.overflow ? Int64.max : logSum.partialValue
                if allocSum.overflow || logSum.overflow { byteOverflow = true }
                if file.isReviewable {
                    eligibleCount += 1
                    totalReclaimable = ByteTotals.adding(totalReclaimable, file.allocatedBytes)
                }
                if let vmCap = file.virtualCapacityBytes {
                    hasVirtualDisk = true
                    let vmSum = virtualTotalAcc.addingReportingOverflow(vmCap)
                    if vmSum.overflow { virtualOverflow = true } else { virtualTotalAcc = vmSum.partialValue }
                }
            }
            if byteOverflow {
                hadPartialItem = true
                partialReasons.append("byte_total_overflow")
            }
            let virtualTotal: Int64? = (hasVirtualDisk && !virtualOverflow) ? virtualTotalAcc : nil

            let status: CategoryStatus
            let noteES: String
            let noteEN: String

            if catStats.hitBudgetOrCancelled || hadPartialItem || (!categoryFiles.isEmpty && catStats.accessDeniedCount > 0) {
                status = .partial
                if result.cancelled {
                    noteES = "Análisis cancelado; resultados parciales"
                    noteEN = "Scan cancelled; partial results"
                } else if catStats.hitBudgetOrCancelled {
                    noteES = "Resultados parciales (presupuesto de entradas o tiempo alcanzado)"
                    noteEN = "Partial results (entry or time budget reached)"
                } else if hadPartialItem {
                    let detailES = partialReasons.isEmpty ? "límite por carpeta" : partialReasons.map { MeasurementNotes.describe($0, language: "es") }.joined(separator: ", ")
                    let detailEN = partialReasons.isEmpty ? "per-folder limit" : partialReasons.map { MeasurementNotes.describe($0, language: "en") }.joined(separator: ", ")
                    noteES = "Resultados parciales (\(categoryFiles.count) elementos · \(detailES))"
                    noteEN = "Partial results (\(categoryFiles.count) items · \(detailEN))"
                } else {
                    noteES = "Resultados parciales (\(categoryFiles.count) elementos · \(catStats.accessDeniedCount) rutas sin acceso)"
                    noteEN = "Partial results (\(categoryFiles.count) items · \(catStats.accessDeniedCount) paths inaccessible)"
                }
            } else if !categoryFiles.isEmpty {
                status = .measured
                noteES = "Medido (\(categoryFiles.count) elementos)"
                noteEN = "Measured (\(categoryFiles.count) items)"
            } else if catStats.accessDeniedCount > 0 {
                status = .noAccess
                noteES = "Sin acceso (permisos o autorización de carpeta requeridos)"
                noteEN = "No access (permissions or folder authorization required)"
            } else if catStats.existingBaseRoots == 0 {
                status = .notInstalled
                noteES = "No se encontraron ubicaciones conocidas del catálogo"
                noteEN = "Known catalog locations were not found"
            } else {
                status = .empty
                noteES = "Sin elementos detectados"
                noteEN = "No items detected"
            }

            reportsByCategory[category] = CategoryReport(
                category: category,
                status: status,
                itemCount: categoryFiles.count,
                eligibleCount: eligibleCount,
                allocatedBytes: totalAllocated,
                logicalBytes: totalLogical,
                virtualCapacityBytes: virtualTotal,
                reclaimableBytes: totalReclaimable,
                definedRuleCount: definedCounts[category] ?? 0,
                matchedRuleCount: matchedRuleIDsByCategory[category]?.count ?? 0,
                errors: Array(Set(catStats.errors)).sorted(),
                statusNoteES: noteES,
                statusNoteEN: noteEN
            )
        }

        if !result.cancelled && (Date() >= deadline || result.examined >= configuration.maxEntries) {
            result.errors.append("Scan budget reached; results are partial")
        }

        result.categories = allCategories.compactMap { reportsByCategory[$0] }
        result.files.sort {
            if $0.allocatedBytes != $1.allocatedBytes { return $0.allocatedBytes > $1.allocatedBytes }
            if $0.logicalBytes != $1.logicalBytes { return $0.logicalBytes > $1.logicalBytes }
            return $0.path < $1.path
        }
        if !result.files.isEmpty {
            var allAlloc: Int64 = 0
            var allLog: Int64 = 0
            var anyOverflow = false
            for file in result.files {
                let (a, aOv) = allAlloc.addingReportingOverflow(file.allocatedBytes)
                let (l, lOv) = allLog.addingReportingOverflow(file.logicalBytes)
                if aOv || lOv { anyOverflow = true; break }
                allAlloc = a
                allLog = l
            }
            if anyOverflow {
                result.errors.append("Byte total exceeds representable limit")
            }
        }
        result.complete = !result.cancelled && result.errors.isEmpty && result.categories.allSatisfy {
            $0.status != .partial && $0.status != .pending && $0.status != .noAccess && $0.status != .scanning
        }
        result.finishedAt = Date()

        onProgress?(ScanProgress(
            currentCategory: nil,
            completedCategories: allCategories.count,
            totalCategories: allCategories.count,
            examinedEntries: result.examined,
            categories: result.categories
        ))

        return result
    }
}
