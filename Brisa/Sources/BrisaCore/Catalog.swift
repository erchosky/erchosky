import Foundation

public enum StorageCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case vmContainers = "vm_containers"
    case appCaches = "app_caches"
    case packageCaches = "package_caches"
    case developerCaches = "developer_caches"
    case editorExtensions = "editor_extensions"
    case toolchainsAndSDKs = "toolchains_sdks"
    case agentAndEditorHistory = "agent_editor_history"
    case temporaryFiles = "temporary_files"
    case logsAndCrashes = "logs_crashes"
    case appLeftovers = "app_leftovers"
    case downloadsAndInstallers = "downloads_installers"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .vmContainers: return "cube.transparent"
        case .appCaches: return "square.stack.3d.up"
        case .packageCaches: return "shippingbox"
        case .developerCaches: return "hammer"
        case .editorExtensions: return "puzzlepiece.extension"
        case .toolchainsAndSDKs: return "wrench.and.screwdriver"
        case .agentAndEditorHistory: return "clock.arrow.circlepath"
        case .temporaryFiles: return "hourglass"
        case .logsAndCrashes: return "doc.text.magnifyingglass"
        case .appLeftovers: return "app.dashed"
        case .downloadsAndInstallers: return "arrow.down.circle"
        }
    }

    public var titleES: String {
        switch self {
        case .vmContainers: return "VM y contenedores"
        case .appCaches: return "Cachés de aplicaciones"
        case .packageCaches: return "Cachés de paquetes"
        case .developerCaches: return "Cachés de desarrollo"
        case .editorExtensions: return "Extensiones de editores"
        case .toolchainsAndSDKs: return "Toolchains y SDK"
        case .agentAndEditorHistory: return "Historial de agentes y editores"
        case .temporaryFiles: return "Archivos temporales"
        case .logsAndCrashes: return "Registros y fallos"
        case .appLeftovers: return "Restos de aplicaciones"
        case .downloadsAndInstallers: return "Descargas e instaladores"
        }
    }

    public var titleEN: String {
        switch self {
        case .vmContainers: return "VMs and containers"
        case .appCaches: return "Application caches"
        case .packageCaches: return "Package caches"
        case .developerCaches: return "Developer caches"
        case .editorExtensions: return "Editor extensions"
        case .toolchainsAndSDKs: return "Toolchains and SDKs"
        case .agentAndEditorHistory: return "Agent and editor history"
        case .temporaryFiles: return "Temporary files"
        case .logsAndCrashes: return "Logs and crash reports"
        case .appLeftovers: return "Application leftovers"
        case .downloadsAndInstallers: return "Downloads and installers"
        }
    }

    public var aboutES: String {
        switch self {
        case .vmContainers: return "Imágenes de máquinas virtuales, contenedores y simuladores. Distingue capacidad virtual declarada de bloques asignados en APFS."
        case .appCaches: return "Cachés web, sombreadores GPU, miniaturas y archivos de aceleración de navegadores y aplicaciones."
        case .packageCaches: return "Paquetes descargados por SwiftPM, Homebrew, npm, pnpm, Yarn, pip, uv, Cargo, Gradle y otros gestores."
        case .developerCaches: return "DerivedData de Xcode, cachés de IDE, índices y artefactos de compilación."
        case .editorExtensions: return "Carpetas de extensiones de VS Code, Cursor, Windsurf y editores derivados (solo inventario)."
        case .toolchainsAndSDKs: return "Versiones instaladas de lenguajes, compiladores, SDKs, DeviceSupport, navegadores de prueba y modelos locales."
        case .agentAndEditorHistory: return "Metadatos de tamaño de sesiones, checkpoints y almacenamiento por proyecto sin leer conversaciones (solo inventario)."
        case .temporaryFiles: return "Archivos y carpetas temporales de usuario y sistema."
        case .logsAndCrashes: return "Registros de aplicaciones e informes de fallos (DiagnosticReports)."
        case .appLeftovers: return "Candidatos de soporte, contenedores y preferencias sin aplicación principal detectada (solo inventario)."
        case .downloadsAndInstallers: return "Instaladores (.dmg, .pkg, .xip, .iso), archivos comprimidos y descargas incompletas."
        }
    }

    public var aboutEN: String {
        switch self {
        case .vmContainers: return "Virtual machine disk images, containers and simulators. Distinguishes virtual capacity from APFS allocated blocks."
        case .appCaches: return "Web caches, GPU shaders, thumbnails and acceleration files from browsers and applications."
        case .packageCaches: return "Downloaded packages kept by SwiftPM, Homebrew, npm, pnpm, Yarn, pip, uv, Cargo, Gradle and other managers."
        case .developerCaches: return "Xcode DerivedData, IDE caches, indexes and build artifacts."
        case .editorExtensions: return "Extension folders for VS Code, Cursor, Windsurf and related editors (inventory only)."
        case .toolchainsAndSDKs: return "Installed language versions, compilers, SDKs, DeviceSupport, test browsers and local models."
        case .agentAndEditorHistory: return "Size metadata of sessions, checkpoints and workspace storage without reading conversation contents (inventory only)."
        case .temporaryFiles: return "User and system temporary files and folders."
        case .logsAndCrashes: return "Application logs and crash reports (DiagnosticReports)."
        case .appLeftovers: return "Support folders, containers and preferences with no detected main application (inventory only)."
        case .downloadsAndInstallers: return "Installers (.dmg, .pkg, .xip, .iso), archives and unfinished downloads."
        }
    }

    public var isPrimarilyInventoryOnly: Bool {
        switch self {
        case .vmContainers, .editorExtensions, .agentAndEditorHistory, .appLeftovers:
            return true
        default:
            return false
        }
    }

    public var legacyCategory: Category {
        switch self {
        case .appCaches, .packageCaches, .developerCaches, .temporaryFiles:
            return .cache
        case .logsAndCrashes:
            return .log
        case .vmContainers, .editorExtensions, .toolchainsAndSDKs, .agentAndEditorHistory, .appLeftovers, .downloadsAndInstallers:
            return .other
        }
    }
}

public enum DataTier: String, Codable, CaseIterable, Sendable {
    case regenerable
    case costly
    case userData
    case never
}

public enum CategoryStatus: String, Codable, CaseIterable, Sendable {
    case pending = "pending"
    case scanning = "scanning"
    case measured = "measured"
    case empty = "empty"
    case notInstalled = "not_installed"
    case noAccess = "no_access"
    case partial = "partial"
}

public struct UsageState: Codable, Equatable, Sendable {
    public let status: String // "idle", "active_process", "open_file", "recently_modified", "unknown"
    public let detail: String?
    public init(status: String, detail: String? = nil) {
        self.status = status
        self.detail = detail
    }
    public static let idle = UsageState(status: "idle")
    public static let unknown = UsageState(status: "unknown")
}

public enum CleanupEligibility: String, Codable, CaseIterable, Sendable {
    case eligible = "eligible"
    case inventoryOnly = "inventory_only"
    case lockedNeverSelect = "locked_never_select"
    case lockedActiveProcess = "locked_active_process"
    case lockedOpenFile = "locked_open_file"
    case lockedRecent = "locked_recent"
    case lockedUnverifiedCondition = "locked_unverified_condition"
    case lockedRequiresTypedAdapter = "locked_requires_typed_adapter"
    case lockedDirectoryBundle = "locked_directory_bundle"
    case lockedProtectedScope = "locked_protected_scope"
    case lockedActiveAgent = "locked_active_agent"
}

public struct CategoryReport: Codable, Identifiable, Equatable, Sendable {
    public var id: String { category.rawValue }
    public let category: StorageCategory
    public var status: CategoryStatus
    public var itemCount: Int
    public var eligibleCount: Int
    public var allocatedBytes: Int64
    public var logicalBytes: Int64
    public var virtualCapacityBytes: Int64?
    public var reclaimableBytes: Int64
    public var definedRuleCount: Int
    public var matchedRuleCount: Int
    public var errors: [String]
    public var statusNoteES: String
    public var statusNoteEN: String

    public var hasMeasuredSize: Bool {
        status == .measured || (status == .partial && itemCount > 0)
    }

    public init(
        category: StorageCategory,
        status: CategoryStatus = .pending,
        itemCount: Int = 0,
        eligibleCount: Int = 0,
        allocatedBytes: Int64 = 0,
        logicalBytes: Int64 = 0,
        virtualCapacityBytes: Int64? = nil,
        reclaimableBytes: Int64 = 0,
        definedRuleCount: Int = 0,
        matchedRuleCount: Int = 0,
        errors: [String] = [],
        statusNoteES: String = "Pendiente de análisis",
        statusNoteEN: String = "Pending analysis"
    ) {
        self.category = category
        self.status = status
        self.itemCount = itemCount
        self.eligibleCount = eligibleCount
        self.allocatedBytes = allocatedBytes
        self.logicalBytes = logicalBytes
        self.virtualCapacityBytes = virtualCapacityBytes
        self.reclaimableBytes = reclaimableBytes
        self.definedRuleCount = definedRuleCount
        self.matchedRuleCount = matchedRuleCount
        self.errors = errors
        self.statusNoteES = statusNoteES
        self.statusNoteEN = statusNoteEN
    }

    public static func defaultPending(definedRulesByCategory: [StorageCategory: Int] = [:]) -> [CategoryReport] {
        StorageCategory.allCases.map { cat in
            CategoryReport(
                category: cat,
                status: .pending,
                definedRuleCount: definedRulesByCategory[cat] ?? 0,
                statusNoteES: "Pendiente de análisis",
                statusNoteEN: "Pending analysis"
            )
        }
    }
}

public struct ScanProgress: Codable, Equatable, Sendable {
    public var currentCategory: StorageCategory?
    public var completedCategories: Int
    public var totalCategories: Int
    public var examinedEntries: Int
    public var categories: [CategoryReport]

    public init(
        currentCategory: StorageCategory? = nil,
        completedCategories: Int = 0,
        totalCategories: Int = StorageCategory.allCases.count,
        examinedEntries: Int = 0,
        categories: [CategoryReport] = CategoryReport.defaultPending()
    ) {
        self.currentCategory = currentCategory
        self.completedCategories = completedCategories
        self.totalCategories = totalCategories
        self.examinedEntries = examinedEntries
        self.categories = categories
    }
}

public struct CatalogRuleCondition: Codable, Equatable, Sendable {
    public var untouchedDays: Int?
    public var projectUntouchedDays: Int?
    public var newestAfterDays: Int?
    public var processes: [String]?
    public var appNotRunning: Bool?
    public var appNotInstalled: Bool?
    public var knownApp: Bool?
    public var notApple: Bool?
    public var keepNewest: Int?
    public var keepBy: String?
    public var keepActive: [String]?
    public var keepPinned: String?
    public var workspaceMissing: Bool?
    public var simulatorDevice: Bool?
    public var deviceBuild: Bool?
    public var minBytes: Int64?
    public var early: Bool?

    public init(
        untouchedDays: Int? = nil,
        projectUntouchedDays: Int? = nil,
        newestAfterDays: Int? = nil,
        processes: [String]? = nil,
        appNotRunning: Bool? = nil,
        appNotInstalled: Bool? = nil,
        knownApp: Bool? = nil,
        notApple: Bool? = nil,
        keepNewest: Int? = nil,
        keepBy: String? = nil,
        keepActive: [String]? = nil,
        keepPinned: String? = nil,
        workspaceMissing: Bool? = nil,
        simulatorDevice: Bool? = nil,
        deviceBuild: Bool? = nil,
        minBytes: Int64? = nil,
        early: Bool? = nil
    ) {
        self.untouchedDays = untouchedDays
        self.projectUntouchedDays = projectUntouchedDays
        self.newestAfterDays = newestAfterDays
        self.processes = processes
        self.appNotRunning = appNotRunning
        self.appNotInstalled = appNotInstalled
        self.knownApp = knownApp
        self.notApple = notApple
        self.keepNewest = keepNewest
        self.keepBy = keepBy
        self.keepActive = keepActive
        self.keepPinned = keepPinned
        self.workspaceMissing = workspaceMissing
        self.simulatorDevice = simulatorDevice
        self.deviceBuild = deviceBuild
        self.minBytes = minBytes
        self.early = early
    }
}

public struct RuleProvenance: Codable, Equatable, Sendable {
    public let repository: String
    public let commit: String
    public let version: String
    public let upstreamID: String
    public let upstreamActionKind: String
    public let coverageRelation: String
    public let localReviewNote: String
    public var license: String { "MIT" }

    public init(
        repository: String = "https://github.com/bmcreations/disk-jockey",
        commit: String = "f28f7e1914dcc74d7c29b0cebda516fb9394ba20",
        version: String = "0.3.0",
        upstreamID: String,
        upstreamActionKind: String,
        coverageRelation: String,
        localReviewNote: String
    ) {
        self.repository = repository
        self.commit = commit
        self.version = version
        self.upstreamID = upstreamID
        self.upstreamActionKind = upstreamActionKind
        self.coverageRelation = coverageRelation
        self.localReviewNote = localReviewNote
    }
}

public struct CatalogRule: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let sourceGroup: String
    public let isPrimaryCategoryGroup: Bool
    public let displayCategory: String // StorageCategory.rawValue or "never_touched"
    public let titleES: String
    public let titleEN: String
    public let explanationES: String
    public let explanationEN: String
    public let regenBehavior: String
    public let patterns: [String]
    public let tier: DataTier
    public let listOnly: Bool
    public let neverTicked: Bool
    public let near: [String]
    public let inside: [String]
    public let notInside: [String]
    public let rule: CatalogRuleCondition
    public let smartRuleSummary: String?
    public let hasUnverifiedCondition: Bool
    public let requiresTypedAdapter: Bool
    public let adapterTool: String?
    public let provenance: String?
    public let upstreamProvenance: RuleProvenance?

    public var storageCategory: StorageCategory? {
        StorageCategory(rawValue: displayCategory)
    }

    public init(
        id: String,
        sourceGroup: String,
        isPrimaryCategoryGroup: Bool = true,
        displayCategory: String,
        titleES: String,
        titleEN: String,
        explanationES: String,
        explanationEN: String,
        regenBehavior: String = "gone",
        patterns: [String],
        tier: DataTier = .costly,
        listOnly: Bool = true,
        neverTicked: Bool = false,
        near: [String] = [],
        inside: [String] = [],
        notInside: [String] = [],
        rule: CatalogRuleCondition = CatalogRuleCondition(),
        smartRuleSummary: String? = nil,
        hasUnverifiedCondition: Bool = false,
        requiresTypedAdapter: Bool = false,
        adapterTool: String? = nil,
        provenance: String? = nil,
        upstreamProvenance: RuleProvenance? = nil
    ) {
        self.id = id
        self.sourceGroup = sourceGroup
        self.isPrimaryCategoryGroup = isPrimaryCategoryGroup
        self.displayCategory = displayCategory
        self.titleES = titleES
        self.titleEN = titleEN
        self.explanationES = explanationES
        self.explanationEN = explanationEN
        self.regenBehavior = regenBehavior
        self.patterns = patterns
        self.tier = tier
        self.listOnly = listOnly
        self.neverTicked = neverTicked
        self.near = near
        self.inside = inside
        self.notInside = notInside
        self.rule = rule
        self.smartRuleSummary = smartRuleSummary
        self.hasUnverifiedCondition = hasUnverifiedCondition
        self.requiresTypedAdapter = requiresTypedAdapter
        self.adapterTool = adapterTool
        self.provenance = provenance
        self.upstreamProvenance = upstreamProvenance
    }
}

public struct CatalogCategoryDescriptor: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let titleES: String
    public let titleEN: String
    public let icon: String
    public let whatItIsES: String
    public let whatItIsEN: String
    public let whySafeES: String
    public let whySafeEN: String
    public let howItComesBackES: String
    public let howItComesBackEN: String
}

public struct StorageCatalog: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let catalogName: String
    public let categories: [CatalogCategoryDescriptor]
    public let rules: [CatalogRule]
    public let diskJockeyRules: [CatalogRule]

    enum CodingKeys: String, CodingKey {
        case schemaVersion, catalogName, categories, rules, diskJockeyRules
    }

    public init(
        schemaVersion: Int,
        catalogName: String,
        categories: [CatalogCategoryDescriptor],
        rules: [CatalogRule],
        diskJockeyRules: [CatalogRule] = []
    ) {
        self.schemaVersion = schemaVersion
        self.catalogName = catalogName
        self.categories = categories
        self.rules = rules
        self.diskJockeyRules = diskJockeyRules
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        catalogName = try c.decode(String.self, forKey: .catalogName)
        categories = try c.decode([CatalogCategoryDescriptor].self, forKey: .categories)
        rules = try c.decode([CatalogRule].self, forKey: .rules)
        diskJockeyRules = try c.decodeIfPresent([CatalogRule].self, forKey: .diskJockeyRules) ?? []
    }

    public var allRules: [CatalogRule] {
        rules + diskJockeyRules
    }

    public var primaryRuleCountsByCategory: [StorageCategory: Int] {
        var counts: [StorageCategory: Int] = [:]
        for cat in StorageCategory.allCases { counts[cat] = 0 }
        for rule in rules where rule.isPrimaryCategoryGroup {
            if let cat = rule.storageCategory {
                counts[cat, default: 0] += 1
            }
        }
        return counts
    }

    public var ruleCountsByCategory: [StorageCategory: Int] {
        Dictionary(grouping: allRules.compactMap(\.storageCategory), by: { $0 }).mapValues(\.count)
    }

    public func rules(for category: StorageCategory, includeExtended: Bool = true) -> [CatalogRule] {
        allRules.filter {
            $0.displayCategory == category.rawValue && (includeExtended || $0.isPrimaryCategoryGroup)
        }
    }

    public var neverTouchedRules: [CatalogRule] {
        allRules.filter { $0.displayCategory == "never_touched" || $0.tier == .never }
    }
}

public struct LoadedCatalog: Sendable {
    public let catalog: StorageCatalog
    public let sourceURL: URL
    public let sourceKind: String // "explicit_url", "explicit_bundle", "app_bundle", "executable_bundle", "swiftpm_module"
}

public enum CatalogLoader {
    public static let resourceFileName = "brisa-catalog"
    public static let resourceExtension = "json"
    private struct CacheKey: Hashable {
        let urlPath: String
        let mtime: TimeInterval
        let sourceKind: String
    }
    private static let cacheLock = NSLock()
    private static var cached: [CacheKey: LoadedCatalog] = [:]

    public static func load(from bundle: Bundle? = nil, url: URL? = nil) throws -> LoadedCatalog {
        if let url {
            return try decode(from: url, sourceKind: "explicit_url")
        }
        if let bundle {
            let kind = bundle.bundleURL.pathExtension == "app" ? "app_bundle" : "explicit_bundle"
            if let direct = bundle.url(forResource: resourceFileName, withExtension: resourceExtension) {
                return try decode(from: direct, sourceKind: kind)
            }
            if let nested = bundle.resourceURL?.appendingPathComponent("Brisa_BrisaCore.bundle/\(resourceFileName).\(resourceExtension)"),
               FileManager.default.fileExists(atPath: nested.path) {
                return try decode(from: nested, sourceKind: kind)
            }
            throw BrisaError.unavailable("Catalog resource missing in specified bundle")
        }

        // 1. Check packaged .app main bundle resources first
        if let mainResource = Bundle.main.resourceURL {
            let direct = mainResource.appendingPathComponent("\(resourceFileName).\(resourceExtension)")
            if FileManager.default.fileExists(atPath: direct.path) {
                return try decode(from: direct, sourceKind: "app_bundle")
            }
            let nested = mainResource.appendingPathComponent("Brisa_BrisaCore.bundle/\(resourceFileName).\(resourceExtension)")
            if FileManager.default.fileExists(atPath: nested.path) {
                return try decode(from: nested, sourceKind: "app_bundle")
            }
        }

        // 2. Check next to executable (for standalone CLI / dist binaries)
        if let arg0 = CommandLine.arguments.first {
            let execDir = URL(fileURLWithPath: arg0).standardizedFileURL.deletingLastPathComponent()
            let candidates = [
                execDir.appendingPathComponent("Brisa_BrisaCore.bundle/\(resourceFileName).\(resourceExtension)"),
                execDir.appendingPathComponent("Brisa.app/Contents/Resources/\(resourceFileName).\(resourceExtension)"),
                execDir.appendingPathComponent("../Resources/\(resourceFileName).\(resourceExtension)").standardizedFileURL
            ]
            for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
                return try decode(from: candidate, sourceKind: "executable_bundle")
            }
        }

        // 3. Fallback to SwiftPM Bundle.module
        if let moduleURL = Bundle.module.url(forResource: resourceFileName, withExtension: resourceExtension) {
            return try decode(from: moduleURL, sourceKind: "swiftpm_module")
        }

        throw BrisaError.unavailable("Could not locate brisa-catalog.json in app bundle or SwiftPM module")
    }

    private static func decode(from url: URL, sourceKind: String) throws -> LoadedCatalog {
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate?.timeIntervalSince1970) ?? 0
        let key = CacheKey(urlPath: url.path, mtime: mtime, sourceKind: sourceKind)
        cacheLock.lock()
        if let hit = cached[key] {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        let data = try Data(contentsOf: url)
        let catalog = try JSONDecoder().decode(StorageCatalog.self, from: data)
        guard catalog.schemaVersion == 1, !catalog.rules.isEmpty else {
            throw BrisaError.invalid("Invalid catalog schema or empty rule set")
        }
        let categories = catalog.categories.map(\.id)
        let ruleIDs = catalog.allRules.map(\.id)
        guard Set(categories) == Set(StorageCategory.allCases.map(\.rawValue)), Set(categories).count == categories.count,
              Set(ruleIDs).count == ruleIDs.count else {
            throw BrisaError.invalid("Catalog must define each category once and use unique rule IDs")
        }
        let loaded = LoadedCatalog(catalog: catalog, sourceURL: url, sourceKind: sourceKind)
        cacheLock.lock()
        if cached.count >= 8 { cached.removeAll(keepingCapacity: true) }
        cached[key] = loaded
        cacheLock.unlock()
        return loaded
    }
}
