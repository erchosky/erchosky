import Foundation

/// Supported developer package managers with dedicated typed adapters.
public enum PackageManagerKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case homebrew
    case npm
    case pnpm
    case yarn

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .homebrew: return "Homebrew"
        case .npm: return "npm"
        case .pnpm: return "pnpm"
        case .yarn: return "Yarn"
        }
    }
}

/// Exact cleanup scope supported by a given package manager command.
public enum PackageManagerCacheScope: String, Codable, Equatable, Sendable {
    /// Clears or verifies the entire global cache store (no per-package selection supported).
    case entireCache = "entire_cache"
    /// Prunes only outdated/unreferenced cache/store entries while keeping current active ones.
    case unreferencedAndOutdated = "unreferenced_and_outdated"
    /// Variant or configuration does not expose a safe global cache cleanup command.
    case unsupportedForGlobalCleanup = "unsupported_for_global_cleanup"
}

/// A documented, version-compatible operation exposed by a package manager adapter.
public struct PackageManagerOperationCapability: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: PackageManagerKind
    public let titleES: String
    public let titleEN: String
    public let descriptionES: String
    public let descriptionEN: String
    public let commandPreview: String
    public let executable: String
    public let arguments: [String]
    public let environmentOverrides: [String: String]
    public let scope: PackageManagerCacheScope
    public let measuredCacheBytes: Int64?
    public let estimatedReclaimableBytes: Int64?
    public let sizeBasis: SizeMeasurementBasis
    public let previewedItems: [String]
    public let preservedSummaryES: String
    public let preservedSummaryEN: String
    public let regenerationES: String
    public let regenerationEN: String
    public let isAvailable: Bool
    public let unavailableReasonES: String?
    public let unavailableReasonEN: String?

    public init(
        id: String,
        kind: PackageManagerKind,
        titleES: String,
        titleEN: String,
        descriptionES: String,
        descriptionEN: String,
        commandPreview: String,
        executable: String,
        arguments: [String],
        environmentOverrides: [String: String] = [:],
        scope: PackageManagerCacheScope,
        measuredCacheBytes: Int64? = nil,
        estimatedReclaimableBytes: Int64? = nil,
        sizeBasis: SizeMeasurementBasis,
        previewedItems: [String] = [],
        preservedSummaryES: String,
        preservedSummaryEN: String,
        regenerationES: String,
        regenerationEN: String,
        isAvailable: Bool,
        unavailableReasonES: String? = nil,
        unavailableReasonEN: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.titleES = titleES
        self.titleEN = titleEN
        self.descriptionES = descriptionES
        self.descriptionEN = descriptionEN
        self.commandPreview = commandPreview
        self.executable = executable
        self.arguments = arguments
        self.environmentOverrides = environmentOverrides
        self.scope = scope
        self.measuredCacheBytes = measuredCacheBytes
        self.estimatedReclaimableBytes = estimatedReclaimableBytes
        self.sizeBasis = sizeBasis
        self.previewedItems = previewedItems
        self.preservedSummaryES = preservedSummaryES
        self.preservedSummaryEN = preservedSummaryEN
        self.regenerationES = regenerationES
        self.regenerationEN = regenerationEN
        self.isAvailable = isAvailable
        self.unavailableReasonES = unavailableReasonES
        self.unavailableReasonEN = unavailableReasonEN
    }
}

/// Complete inspection snapshot for one package manager installation.
public struct PackageManagerInspection: Codable, Equatable, Sendable, Identifiable {
    public var id: String { kind.rawValue }
    public let kind: PackageManagerKind
    public let displayName: String
    public let executablePath: String?
    public let versionString: String?
    public let majorVersion: Int?
    public let variantLabel: String?
    public let isInstalled: Bool
    public let cachePaths: [String]
    public let cacheAllocatedBytes: Int64?
    public let cacheLogicalBytes: Int64?
    public let cacheMeasurementPartial: Bool
    public let installedPackagesPaths: [String]
    public let preservedSummaryES: String
    public let preservedSummaryEN: String
    public let capabilities: [PackageManagerOperationCapability]
    public let warningsES: [String]
    public let warningsEN: [String]
    public let inspectionError: String?

    public init(
        kind: PackageManagerKind,
        displayName: String? = nil,
        executablePath: String?,
        versionString: String?,
        majorVersion: Int?,
        variantLabel: String? = nil,
        isInstalled: Bool,
        cachePaths: [String],
        cacheAllocatedBytes: Int64?,
        cacheLogicalBytes: Int64?,
        cacheMeasurementPartial: Bool = false,
        installedPackagesPaths: [String] = [],
        preservedSummaryES: String,
        preservedSummaryEN: String,
        capabilities: [PackageManagerOperationCapability],
        warningsES: [String] = [],
        warningsEN: [String] = [],
        inspectionError: String? = nil
    ) {
        self.kind = kind
        self.displayName = displayName ?? kind.displayName
        self.executablePath = executablePath
        self.versionString = versionString
        self.majorVersion = majorVersion
        self.variantLabel = variantLabel
        self.isInstalled = isInstalled
        self.cachePaths = cachePaths
        self.cacheAllocatedBytes = cacheAllocatedBytes
        self.cacheLogicalBytes = cacheLogicalBytes
        self.cacheMeasurementPartial = cacheMeasurementPartial
        self.installedPackagesPaths = installedPackagesPaths
        self.preservedSummaryES = preservedSummaryES
        self.preservedSummaryEN = preservedSummaryEN
        self.capabilities = capabilities
        self.warningsES = warningsES
        self.warningsEN = warningsEN
        self.inspectionError = inspectionError
    }
}

/// Protocol implemented by each independent package manager adapter.
public protocol PackageManagerAdapter: Sendable {
    var kind: PackageManagerKind { get }
    func inspect(control: ScanControl) -> PackageManagerInspection
}

/// Shared measurement & semver parsing helpers for package manager adapters.
enum PackageManagerInspectionHelpers {
    struct MeasuredCacheDirectories {
        let allocatedBytes: Int64?
        let logicalBytes: Int64?
        let isPartial: Bool
    }

    static func parseFirstSemver(_ text: String) -> (version: String, major: Int)? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)\.(\d+)(?:\.(\d+))?"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let fullRange = Range(match.range, in: text),
              let majorRange = Range(match.range(at: 1), in: text),
              let major = Int(text[majorRange]) else {
            return nil
        }
        return (String(text[fullRange]), major)
    }

    static func measureDirectories(
        _ paths: [String],
        home: String,
        readPolicy: ReadAuthorizationPolicy,
        control: ScanControl
    ) -> MeasuredCacheDirectories {
        var totalAlloc: Int64 = 0
        var totalLogical: Int64 = 0
        var anyMeasured = false
        var partial = false
        var seenInodes = Set<InodeKey>()
        var examined = 0

        for raw in paths {
            let path = Paths.normalized(raw)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { continue }
            if let measured = StorageMeasurement.measure(
                path: path,
                category: .developerCaches,
                readPolicy: readPolicy,
                claimedPaths: [],
                neverTouchedPaths: [],
                seenInodes: &seenInodes,
                cancellation: control.cancellation,
                maxEntriesPerItem: 150_000,
                examinedCounter: &examined,
                deadline: control.deadline
            ) {
                anyMeasured = true
                totalAlloc = ByteTotals.adding(totalAlloc, measured.allocatedBytes)
                totalLogical = ByteTotals.adding(totalLogical, measured.logicalBytes)
                if measured.isPartial || measured.skippedProtectedChild {
                    partial = true
                }
            }
        }

        return MeasuredCacheDirectories(
            allocatedBytes: anyMeasured ? totalAlloc : nil,
            logicalBytes: anyMeasured ? totalLogical : nil,
            isPartial: partial
        )
    }

    /// Parses human byte suffixes such as `12.4MB`, `3.2GB`, `450KB`, `1.2GiB`, `512B`.
    static func parseHumanBytes(_ raw: String) -> Int64? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: #"^([0-9]+(?:\.[0-9]+)?)\s*([KMGT]?i?B)$"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let numRange = Range(match.range(at: 1), in: trimmed),
              let unitRange = Range(match.range(at: 2), in: trimmed),
              let value = Double(trimmed[numRange]) else {
            return nil
        }
        let unit = trimmed[unitRange].uppercased()
        let multiplier: Double
        switch unit {
        case "B": multiplier = 1
        case "KB": multiplier = 1_000
        case "KIB": multiplier = 1_024
        case "MB": multiplier = 1_000_000
        case "MIB": multiplier = 1_048_576
        case "GB": multiplier = 1_000_000_000
        case "GIB": multiplier = 1_073_741_824
        case "TB": multiplier = 1_000_000_000_000
        case "TIB": multiplier = 1_099_511_627_776
        default: return nil
        }
        guard (value * multiplier).isFinite, value * multiplier < Double(Int64.max) else { return nil }
        return Int64(value * multiplier)
    }

    static func existingPaths(_ candidates: [String]) -> [String] {
        candidates.map(Paths.normalized).filter { FileManager.default.fileExists(atPath: $0) }
    }
}

// MARK: - 1. Homebrew Adapter

public struct HomebrewAdapter: PackageManagerAdapter {
    public let kind: PackageManagerKind = .homebrew
    private let executor: CommandExecuting
    private let home: String
    private let readPolicy: ReadAuthorizationPolicy
    private let explicitExecutable: String?

    public init(
        executor: CommandExecuting = LiveCommandExecutor(),
        home: String = NSHomeDirectory(),
        readPolicy: ReadAuthorizationPolicy? = nil,
        executable: String? = nil
    ) {
        self.executor = executor
        self.home = Paths.normalized(home)
        self.readPolicy = readPolicy ?? ReadAuthorizationPolicy(home: self.home)
        self.explicitExecutable = executable
    }

    public func inspect(control: ScanControl = ScanControl()) -> PackageManagerInspection {
        let preservedES = "Se conservan las fórmulas y casks instalados (Cellar/Caskroom), los taps configurados y los ajustes de Homebrew."
        let preservedEN = "Installed formulae and casks (Cellar/Caskroom), taps, and Homebrew configuration remain untouched."
        let installedDirs = PackageManagerInspectionHelpers.existingPaths([
            "/opt/homebrew/Cellar",
            "/opt/homebrew/Caskroom",
            "/usr/local/Cellar",
            "/usr/local/Caskroom"
        ])

        guard let brewPath = explicitExecutable ?? ExecutableLocator.resolve(name: "brew", home: home) else {
            return PackageManagerInspection(
                kind: .homebrew,
                executablePath: nil,
                versionString: nil,
                majorVersion: nil,
                isInstalled: false,
                cachePaths: [],
                cacheAllocatedBytes: nil,
                cacheLogicalBytes: nil,
                installedPackagesPaths: installedDirs,
                preservedSummaryES: preservedES,
                preservedSummaryEN: preservedEN,
                capabilities: []
            )
        }

        let verResult = try? executor.run(
            CommandExecutionRequest(executable: brewPath, arguments: ["--version"], timeout: 10),
            control: control
        )
        guard let verResult, !verResult.timedOut, verResult.status == 0,
              let parsedVer = PackageManagerInspectionHelpers.parseFirstSemver(verResult.output) else {
            return PackageManagerInspection(
                kind: .homebrew,
                executablePath: brewPath,
                versionString: nil,
                majorVersion: nil,
                isInstalled: true,
                cachePaths: [],
                cacheAllocatedBytes: nil,
                cacheLogicalBytes: nil,
                installedPackagesPaths: installedDirs,
                preservedSummaryES: preservedES,
                preservedSummaryEN: preservedEN,
                capabilities: [],
                inspectionError: verResult?.error.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                    ?? "Could not query Homebrew version"
            )
        }

        let cacheBox = LockedBox<CommandResult?>(nil)
        let emptyPreview = DryRunPreview(items: [], estimatedBytes: nil, failed: false, errorMessage: nil)
        let stdBox = LockedBox<DryRunPreview>(emptyPreview)
        let scrubBox = LockedBox<DryRunPreview>(emptyPreview)

        if !control.shouldStop {
            let group = DispatchGroup()
            let workerQueue = DispatchQueue.global(qos: .userInitiated)
            let semaphore = DispatchSemaphore(value: 3)

            group.enter()
            workerQueue.async {
                semaphore.wait()
                defer { semaphore.signal(); group.leave() }
                cacheBox.set(try? self.executor.run(
                    CommandExecutionRequest(executable: brewPath, arguments: ["--cache"], timeout: 10),
                    control: control
                ))
            }

            group.enter()
            workerQueue.async {
                semaphore.wait()
                defer { semaphore.signal(); group.leave() }
                stdBox.set(self.parseDryRun(
                    executor: self.executor,
                    executable: brewPath,
                    arguments: ["cleanup", "--dry-run"],
                    control: control
                ))
            }

            group.enter()
            workerQueue.async {
                semaphore.wait()
                defer { semaphore.signal(); group.leave() }
                scrubBox.set(self.parseDryRun(
                    executor: self.executor,
                    executable: brewPath,
                    arguments: ["cleanup", "-s", "--dry-run"],
                    control: control
                ))
            }
            group.wait()
        }

        let cacheResult = cacheBox.get()
        let stdDryRun = stdBox.get()
        let scrubDryRun = scrubBox.get()

        let cacheDir = cacheResult?.status == 0
            ? cacheResult?.output.split(separator: "\n").first.map { Paths.normalized(String($0)) }
            : Paths.normalized(home + "/Library/Caches/Homebrew")
        let cachePaths = cacheDir.map { [$0] } ?? []
        let measured = PackageManagerInspectionHelpers.measureDirectories(
            cachePaths,
            home: home,
            readPolicy: readPolicy,
            control: control
        )

        let supportsCleanup = parsedVer.major >= 2
        let capStandard = PackageManagerOperationCapability(
            id: "brew.cleanup.standard",
            kind: .homebrew,
            titleES: "Limpiar versiones antiguas y descargas obsoletas",
            titleEN: "Clean outdated versions and stale downloads",
            descriptionES: "Ejecuta brew cleanup para borrar lockfiles antiguos, versiones previas ya sustituidas y descargas de más de 120 días.",
            descriptionEN: "Runs brew cleanup to remove stale locks, superseded formula versions, and downloads older than 120 days.",
            commandPreview: "brew cleanup",
            executable: brewPath,
            arguments: ["cleanup"],
            scope: .unreferencedAndOutdated,
            measuredCacheBytes: measured.allocatedBytes,
            estimatedReclaimableBytes: stdDryRun.estimatedBytes,
            sizeBasis: stdDryRun.estimatedBytes != nil ? .estimated : (measured.allocatedBytes != nil ? .measured : .estimated),
            previewedItems: stdDryRun.items,
            preservedSummaryES: preservedES + " Se conservan también las descargas recientes (<120 días).",
            preservedSummaryEN: preservedEN + " Recent cached downloads (<120 days) are also kept.",
            regenerationES: "Homebrew vuelve a descargar automáticamente el paquete o bottle al reinstalar o actualizar.",
            regenerationEN: "Homebrew automatically re-downloads bottles or casks when reinstalling or upgrading.",
            isAvailable: supportsCleanup && !stdDryRun.failed,
            unavailableReasonES: !supportsCleanup ? "Versión de Homebrew no compatible." : stdDryRun.errorMessage,
            unavailableReasonEN: !supportsCleanup ? "Unsupported Homebrew version." : stdDryRun.errorMessage
        )

        let capScrub = PackageManagerOperationCapability(
            id: "brew.cleanup.scrub",
            kind: .homebrew,
            titleES: "Depurar toda la caché de descargas (--scrub)",
            titleEN: "Scrub cached downloads (--scrub)",
            descriptionES: "Ejecuta brew cleanup -s para eliminar también descargas recientes de fórmulas/casks, manteniendo las instalaciones activas.",
            descriptionEN: "Runs brew cleanup -s to also prune recent cached downloads while keeping installed formulae and casks intact.",
            commandPreview: "brew cleanup -s",
            executable: brewPath,
            arguments: ["cleanup", "-s"],
            scope: .unreferencedAndOutdated,
            measuredCacheBytes: measured.allocatedBytes,
            estimatedReclaimableBytes: scrubDryRun.estimatedBytes,
            sizeBasis: scrubDryRun.estimatedBytes != nil ? .estimated : (measured.allocatedBytes != nil ? .measured : .estimated),
            previewedItems: scrubDryRun.items,
            preservedSummaryES: preservedES,
            preservedSummaryEN: preservedEN,
            regenerationES: "La próxima reinstalación descargará de nuevo los archivos desde los repositorios de Homebrew.",
            regenerationEN: "Next reinstall will fetch required archives from Homebrew bottles/mirrors again.",
            isAvailable: supportsCleanup && !scrubDryRun.failed,
            unavailableReasonES: !supportsCleanup ? "Versión de Homebrew no compatible." : scrubDryRun.errorMessage,
            unavailableReasonEN: !supportsCleanup ? "Unsupported Homebrew version." : scrubDryRun.errorMessage
        )

        var warningsES: [String] = []
        var warningsEN: [String] = []
        if let err = stdDryRun.errorMessage {
            warningsES.append("Vista previa --dry-run incompleta: \(err)")
            warningsEN.append("--dry-run preview incomplete: \(err)")
        }

        return PackageManagerInspection(
            kind: .homebrew,
            executablePath: brewPath,
            versionString: parsedVer.version,
            majorVersion: parsedVer.major,
            isInstalled: true,
            cachePaths: cachePaths,
            cacheAllocatedBytes: measured.allocatedBytes,
            cacheLogicalBytes: measured.logicalBytes,
            cacheMeasurementPartial: measured.isPartial,
            installedPackagesPaths: installedDirs,
            preservedSummaryES: preservedES,
            preservedSummaryEN: preservedEN,
            capabilities: [capStandard, capScrub],
            warningsES: warningsES,
            warningsEN: warningsEN
        )
    }

    private struct DryRunPreview {
        let items: [String]
        let estimatedBytes: Int64?
        let failed: Bool
        let errorMessage: String?
    }

    private func parseDryRun(
        executor: CommandExecuting,
        executable: String,
        arguments: [String],
        control: ScanControl
    ) -> DryRunPreview {
        do {
            let res = try executor.run(
                CommandExecutionRequest(executable: executable, arguments: arguments, timeout: 20),
                control: control
            )
            if res.timedOut {
                return DryRunPreview(items: [], estimatedBytes: nil, failed: true, errorMessage: "Timeout during dry-run")
            }
            guard res.status == 0 else {
                let msg = res.error.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Exit status \(res.status)"
                return DryRunPreview(items: [], estimatedBytes: nil, failed: true, errorMessage: msg)
            }
            var items: [String] = []
            var estimatedBytes: Int64?
            var summedItemBytes: Int64 = 0
            var parsedAnyItemSize = false
            for rawLine in res.output.split(separator: "\n") {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.hasPrefix("Would remove:") {
                    let item = line.replacingOccurrences(of: "Would remove:", with: "").trimmingCharacters(in: .whitespaces)
                    if !item.isEmpty { items.append(item) }
                    if let regex = try? NSRegularExpression(pattern: #"\(([^()]+)\)\s*$"#),
                       let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                       let range = Range(match.range(at: 1), in: line),
                       let parsed = PackageManagerInspectionHelpers.parseHumanBytes(String(line[range])) {
                        summedItemBytes = ByteTotals.adding(summedItemBytes, parsed)
                        parsedAnyItemSize = true
                    }
                } else if line.contains("approximately") {
                    if let regex = try? NSRegularExpression(pattern: #"approximately\s+([0-9]+(?:\.[0-9]+)?\s*[KMGT]?i?B)"#, options: .caseInsensitive),
                       let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                       let range = Range(match.range(at: 1), in: line) {
                        estimatedBytes = PackageManagerInspectionHelpers.parseHumanBytes(String(line[range]))
                    }
                }
            }
            if estimatedBytes == nil && parsedAnyItemSize {
                estimatedBytes = summedItemBytes
            }
            if items.isEmpty && estimatedBytes == nil {
                estimatedBytes = 0
            }
            return DryRunPreview(items: Array(items.prefix(200)), estimatedBytes: estimatedBytes, failed: false, errorMessage: nil)
        } catch {
            return DryRunPreview(items: [], estimatedBytes: nil, failed: true, errorMessage: error.localizedDescription)
        }
    }
}

// MARK: - 2. npm Adapter

public struct NpmAdapter: PackageManagerAdapter {
    public let kind: PackageManagerKind = .npm
    private let executor: CommandExecuting
    private let home: String
    private let readPolicy: ReadAuthorizationPolicy
    private let explicitExecutable: String?

    public init(
        executor: CommandExecuting = LiveCommandExecutor(),
        home: String = NSHomeDirectory(),
        readPolicy: ReadAuthorizationPolicy? = nil,
        executable: String? = nil
    ) {
        self.executor = executor
        self.home = Paths.normalized(home)
        self.readPolicy = readPolicy ?? ReadAuthorizationPolicy(home: self.home)
        self.explicitExecutable = executable
    }

    public func inspect(control: ScanControl = ScanControl()) -> PackageManagerInspection {
        let preservedES = "Se conservan las dependencias instaladas (globales y node_modules de proyectos), ~/.npmrc y tokens de sesión."
        let preservedEN = "Installed packages (global & project node_modules), ~/.npmrc, and auth credentials remain untouched."

        guard let npmPath = explicitExecutable ?? ExecutableLocator.resolve(name: "npm", home: home) else {
            return PackageManagerInspection(
                kind: .npm,
                executablePath: nil,
                versionString: nil,
                majorVersion: nil,
                isInstalled: false,
                cachePaths: [],
                cacheAllocatedBytes: nil,
                cacheLogicalBytes: nil,
                preservedSummaryES: preservedES,
                preservedSummaryEN: preservedEN,
                capabilities: []
            )
        }

        let binDir = URL(fileURLWithPath: npmPath).deletingLastPathComponent().path
        let cwd = URL(fileURLWithPath: home, isDirectory: true)
        let verResult = try? executor.run(
            CommandExecutionRequest(executable: npmPath, arguments: ["--version"], timeout: 10, directory: cwd, extraPATHDirectories: [binDir]),
            control: control
        )
        guard let verResult, !verResult.timedOut, verResult.status == 0,
              let parsedVer = PackageManagerInspectionHelpers.parseFirstSemver(verResult.output) else {
            return PackageManagerInspection(
                kind: .npm,
                executablePath: npmPath,
                versionString: nil,
                majorVersion: nil,
                isInstalled: true,
                cachePaths: [],
                cacheAllocatedBytes: nil,
                cacheLogicalBytes: nil,
                preservedSummaryES: preservedES,
                preservedSummaryEN: preservedEN,
                capabilities: [],
                inspectionError: verResult?.error.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                    ?? "Could not determine npm version"
            )
        }

        let cacheConfigRes = try? executor.run(
            CommandExecutionRequest(executable: npmPath, arguments: ["config", "get", "cache"], timeout: 10, directory: cwd, extraPATHDirectories: [binDir]),
            control: control
        )
        let rawCache = cacheConfigRes?.status == 0
            ? cacheConfigRes?.output.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        let cacheDir = (rawCache?.nonEmpty).map(Paths.normalized) ?? Paths.normalized(home + "/.npm")
        let cachePaths = [cacheDir]
        let measured = PackageManagerInspectionHelpers.measureDirectories(
            cachePaths,
            home: home,
            readPolicy: readPolicy,
            control: control
        )

        var installedDirs: [String] = []
        if let rootRes = try? executor.run(
            CommandExecutionRequest(executable: npmPath, arguments: ["root", "-g"], timeout: 10, directory: cwd, extraPATHDirectories: [binDir]),
            control: control
        ), rootRes.status == 0, let line = rootRes.output.split(separator: "\n").first {
            let norm = Paths.normalized(String(line))
            if FileManager.default.fileExists(atPath: norm) {
                installedDirs.append(norm)
            }
        }

        let isModernCAS = parsedVer.major >= 5
        var capabilities: [PackageManagerOperationCapability] = []

        if isModernCAS {
            capabilities.append(PackageManagerOperationCapability(
                id: "npm.cache.verify",
                kind: .npm,
                titleES: "Verificar y recolectar basura del caché (npm cache verify)",
                titleEN: "Verify and garbage-collect cache (npm cache verify)",
                descriptionES: "Operación recomendada en npm v5+: verifica integridad del índice _cacache y elimina únicamente objetos sin referencia.",
                descriptionEN: "Official npm v5+ operation: checks _cacache integrity and garbage-collects unreferenced content only.",
                commandPreview: "npm cache verify",
                executable: npmPath,
                arguments: ["cache", "verify"],
                scope: .unreferencedAndOutdated,
                measuredCacheBytes: measured.allocatedBytes,
                estimatedReclaimableBytes: nil,
                sizeBasis: .estimated,
                preservedSummaryES: preservedES + " También conserva los paquetes cacheados que siguen indexados.",
                preservedSummaryEN: preservedEN + " Valid indexed cache entries are also kept.",
                regenerationES: "Las entradas eliminadas ya no estaban referenciadas; si se necesitan luego se descargan del registro.",
                regenerationEN: "Removed entries were unreferenced; future installs re-fetch from the npm registry if needed.",
                isAvailable: true
            ))
        }

        let forceRequired = isModernCAS
        let cleanArgs = forceRequired ? ["cache", "clean", "--force"] : ["cache", "clean"]
        let previewCmd = forceRequired ? "npm cache clean --force" : "npm cache clean"
        capabilities.append(PackageManagerOperationCapability(
            id: "npm.cache.clean",
            kind: .npm,
            titleES: "Vaciar toda la caché global de npm",
            titleEN: "Clean entire global npm cache",
            descriptionES: isModernCAS
                ? "Alcance completo: npm v\(parsedVer.major) usa un almacén opaco _cacache y no permite elegir paquetes individuales. --force borra toda la caché en \(cacheDir)."
                : "Alcance completo: vacía la caché de npm en \(cacheDir).",
            descriptionEN: isModernCAS
                ? "Full-cache scope: npm v\(parsedVer.major) uses an opaque _cacache store and cannot select individual packages. --force clears the entire cache at \(cacheDir)."
                : "Full-cache scope: clears the entire npm cache at \(cacheDir).",
            commandPreview: previewCmd,
            executable: npmPath,
            arguments: cleanArgs,
            scope: .entireCache,
            measuredCacheBytes: measured.allocatedBytes,
            estimatedReclaimableBytes: measured.allocatedBytes,
            sizeBasis: measured.allocatedBytes != nil ? .measured : .estimated,
            preservedSummaryES: preservedES,
            preservedSummaryEN: preservedEN,
            regenerationES: "npm volverá a descargar los paquetes desde el registro en futuras instalaciones.",
            regenerationEN: "npm will re-download tarballs from the registry on future installs.",
            isAvailable: true
        ))

        return PackageManagerInspection(
            kind: .npm,
            executablePath: npmPath,
            versionString: parsedVer.version,
            majorVersion: parsedVer.major,
            variantLabel: isModernCAS ? "npm CAS (_cacache)" : "npm legacy cache",
            isInstalled: true,
            cachePaths: cachePaths,
            cacheAllocatedBytes: measured.allocatedBytes,
            cacheLogicalBytes: measured.logicalBytes,
            cacheMeasurementPartial: measured.isPartial,
            installedPackagesPaths: installedDirs,
            preservedSummaryES: preservedES,
            preservedSummaryEN: preservedEN,
            capabilities: capabilities
        )
    }
}

// MARK: - 3. pnpm Adapter

public struct PnpmAdapter: PackageManagerAdapter {
    public let kind: PackageManagerKind = .pnpm
    private let executor: CommandExecuting
    private let home: String
    private let readPolicy: ReadAuthorizationPolicy
    private let explicitExecutable: String?

    public init(
        executor: CommandExecuting = LiveCommandExecutor(),
        home: String = NSHomeDirectory(),
        readPolicy: ReadAuthorizationPolicy? = nil,
        executable: String? = nil
    ) {
        self.executor = executor
        self.home = Paths.normalized(home)
        self.readPolicy = readPolicy ?? ReadAuthorizationPolicy(home: self.home)
        self.explicitExecutable = executable
    }

    public func inspect(control: ScanControl = ScanControl()) -> PackageManagerInspection {
        let preservedES = "Se conservan todos los paquetes referenciados por tus proyectos, node_modules, lockfiles, .npmrc y credenciales."
        let preservedEN = "Packages still referenced by projects, node_modules, lockfiles, .npmrc, and auth credentials remain untouched."

        guard let pnpmPath = explicitExecutable ?? ExecutableLocator.resolve(name: "pnpm", home: home) else {
            return PackageManagerInspection(
                kind: .pnpm,
                executablePath: nil,
                versionString: nil,
                majorVersion: nil,
                isInstalled: false,
                cachePaths: [],
                cacheAllocatedBytes: nil,
                cacheLogicalBytes: nil,
                preservedSummaryES: preservedES,
                preservedSummaryEN: preservedEN,
                capabilities: []
            )
        }

        let binDir = URL(fileURLWithPath: pnpmPath).deletingLastPathComponent().path
        let cwd = URL(fileURLWithPath: home, isDirectory: true)
        let verResult = try? executor.run(
            CommandExecutionRequest(executable: pnpmPath, arguments: ["--version"], timeout: 10, directory: cwd, extraPATHDirectories: [binDir]),
            control: control
        )
        guard let verResult, !verResult.timedOut, verResult.status == 0,
              let parsedVer = PackageManagerInspectionHelpers.parseFirstSemver(verResult.output) else {
            return PackageManagerInspection(
                kind: .pnpm,
                executablePath: pnpmPath,
                versionString: nil,
                majorVersion: nil,
                isInstalled: true,
                cachePaths: [],
                cacheAllocatedBytes: nil,
                cacheLogicalBytes: nil,
                preservedSummaryES: preservedES,
                preservedSummaryEN: preservedEN,
                capabilities: [],
                inspectionError: verResult?.error.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                    ?? "Could not determine pnpm version"
            )
        }

        let storeRes = try? executor.run(
            CommandExecutionRequest(executable: pnpmPath, arguments: ["store", "path"], timeout: 15, directory: cwd, extraPATHDirectories: [binDir]),
            control: control
        )
        let storePath = storeRes?.status == 0
            ? storeRes?.output.split(separator: "\n").last.map { Paths.normalized(String($0)) }
            : Paths.normalized(home + "/Library/pnpm/store")
        let cachePaths = storePath.map { [$0] } ?? []
        let measured = PackageManagerInspectionHelpers.measureDirectories(
            cachePaths,
            home: home,
            readPolicy: readPolicy,
            control: control
        )

        let supportsPrune = parsedVer.major >= 3
        let pruneCap = PackageManagerOperationCapability(
            id: "pnpm.store.prune",
            kind: .pnpm,
            titleES: "Depurar paquetes no referenciados (pnpm store prune)",
            titleEN: "Prune unreferenced store packages (pnpm store prune)",
            descriptionES: "Elimina del almacén global de pnpm únicamente los paquetes que ya no usa ningún proyecto en el disco; no elimina el almacén completo ni rompe node_modules existentes.",
            descriptionEN: "Removes only unreferenced packages from the pnpm global store; active project packages and node_modules stay intact.",
            commandPreview: "pnpm store prune",
            executable: pnpmPath,
            arguments: ["store", "prune"],
            scope: .unreferencedAndOutdated,
            measuredCacheBytes: measured.allocatedBytes,
            estimatedReclaimableBytes: nil,
            sizeBasis: .estimated,
            preservedSummaryES: preservedES,
            preservedSummaryEN: preservedEN,
            regenerationES: "Si luego haces checkout a una rama antigua, pnpm volverá a descargar las versiones podadas.",
            regenerationEN: "If you later switch back to an older branch or lockfile, pnpm re-downloads pruned packages.",
            isAvailable: supportsPrune,
            unavailableReasonES: supportsPrune ? nil : "pnpm store prune requiere pnpm v3 o superior.",
            unavailableReasonEN: supportsPrune ? nil : "pnpm store prune requires pnpm v3 or newer."
        )

        let installedDirs = PackageManagerInspectionHelpers.existingPaths([
            home + "/Library/pnpm/global",
            home + "/.local/share/pnpm/global"
        ])

        return PackageManagerInspection(
            kind: .pnpm,
            executablePath: pnpmPath,
            versionString: parsedVer.version,
            majorVersion: parsedVer.major,
            variantLabel: "pnpm CAS store",
            isInstalled: true,
            cachePaths: cachePaths,
            cacheAllocatedBytes: measured.allocatedBytes,
            cacheLogicalBytes: measured.logicalBytes,
            cacheMeasurementPartial: measured.isPartial,
            installedPackagesPaths: installedDirs,
            preservedSummaryES: preservedES,
            preservedSummaryEN: preservedEN,
            capabilities: [pruneCap],
            warningsES: ["El espacio recuperado real depende de cuántos paquetes queden sin referencias en store y solo se conoce tras ejecutar la poda."],
            warningsEN: ["Actual reclaimed space depends on how many unreferenced packages exist in the store and is only known after pruning."]
        )
    }
}

// MARK: - 4. Yarn Adapter (Classic v1 vs Berry v2–v4+)

public struct YarnAdapter: PackageManagerAdapter {
    public let kind: PackageManagerKind = .yarn
    private let executor: CommandExecuting
    private let home: String
    private let readPolicy: ReadAuthorizationPolicy
    private let explicitExecutable: String?

    public init(
        executor: CommandExecuting = LiveCommandExecutor(),
        home: String = NSHomeDirectory(),
        readPolicy: ReadAuthorizationPolicy? = nil,
        executable: String? = nil
    ) {
        self.executor = executor
        self.home = Paths.normalized(home)
        self.readPolicy = readPolicy ?? ReadAuthorizationPolicy(home: self.home)
        self.explicitExecutable = executable
    }

    public func inspect(control: ScanControl = ScanControl()) -> PackageManagerInspection {
        let preservedES = "Se conservan paquetes globales instalados, archivos de configuración (.yarnrc, .yarnrc.yml), credenciales y node_modules de proyectos."
        let preservedEN = "Installed global packages, config files (.yarnrc, .yarnrc.yml), credentials, and project node_modules remain untouched."

        guard let yarnPath = explicitExecutable ?? ExecutableLocator.resolve(name: "yarn", home: home) else {
            return PackageManagerInspection(
                kind: .yarn,
                executablePath: nil,
                versionString: nil,
                majorVersion: nil,
                isInstalled: false,
                cachePaths: [],
                cacheAllocatedBytes: nil,
                cacheLogicalBytes: nil,
                preservedSummaryES: preservedES,
                preservedSummaryEN: preservedEN,
                capabilities: []
            )
        }

        let binDir = URL(fileURLWithPath: yarnPath).deletingLastPathComponent().path
        let cwd = URL(fileURLWithPath: home, isDirectory: true)
        let env = ["COREPACK_ENABLE_DOWNLOAD_PROMPT": "0"]
        let verResult = try? executor.run(
            CommandExecutionRequest(
                executable: yarnPath,
                arguments: ["--version"],
                timeout: 10,
                directory: cwd,
                extraPATHDirectories: [binDir],
                environmentOverrides: env
            ),
            control: control
        )
        guard let verResult, !verResult.timedOut, verResult.status == 0,
              let parsedVer = PackageManagerInspectionHelpers.parseFirstSemver(verResult.output) else {
            let errText = verResult?.error.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                ?? verResult?.output.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                ?? "Could not determine Yarn version"
            return PackageManagerInspection(
                kind: .yarn,
                executablePath: yarnPath,
                versionString: nil,
                majorVersion: nil,
                isInstalled: true,
                cachePaths: [],
                cacheAllocatedBytes: nil,
                cacheLogicalBytes: nil,
                preservedSummaryES: preservedES,
                preservedSummaryEN: preservedEN,
                capabilities: [],
                warningsES: ["Si Yarn se gestiona con Corepack y aún no está descargado, requiere activación previa sin modo interactivo."],
                warningsEN: ["If Yarn is managed by Corepack without a cached distribution, it may require prior non-interactive activation."],
                inspectionError: errText
            )
        }

        let isClassic = parsedVer.major < 2
        let installedDirs = PackageManagerInspectionHelpers.existingPaths([
            home + "/.config/yarn/global",
            home + "/.yarn/berry/global"
        ])

        if isClassic {
            let dirRes = try? executor.run(
                CommandExecutionRequest(
                    executable: yarnPath,
                    arguments: ["cache", "dir"],
                    timeout: 10,
                    directory: cwd,
                    extraPATHDirectories: [binDir],
                    environmentOverrides: env
                ),
                control: control
            )
            let rawDir = dirRes?.status == 0
                ? dirRes?.output.split(separator: "\n").last?.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil
            let cacheDir = (rawDir?.nonEmpty).map(Paths.normalized) ?? Paths.normalized(home + "/Library/Caches/Yarn")
            let cachePaths = [cacheDir]
            let measured = PackageManagerInspectionHelpers.measureDirectories(
                cachePaths,
                home: home,
                readPolicy: readPolicy,
                control: control
            )

            let cleanCap = PackageManagerOperationCapability(
                id: "yarn.classic.cache.clean",
                kind: .yarn,
                titleES: "Vaciar la caché global de Yarn Classic (v\(parsedVer.major))",
                titleEN: "Clean global Yarn Classic (v\(parsedVer.major)) cache",
                descriptionES: "Alcance completo: yarn cache clean en Yarn v1 elimina toda la caché global ubicada en \(cacheDir).",
                descriptionEN: "Full-cache scope: yarn cache clean in Yarn v1 removes the entire global cache at \(cacheDir).",
                commandPreview: "yarn cache clean",
                executable: yarnPath,
                arguments: ["cache", "clean"],
                environmentOverrides: env,
                scope: .entireCache,
                measuredCacheBytes: measured.allocatedBytes,
                estimatedReclaimableBytes: measured.allocatedBytes,
                sizeBasis: measured.allocatedBytes != nil ? .measured : .estimated,
                preservedSummaryES: preservedES,
                preservedSummaryEN: preservedEN,
                regenerationES: "Yarn Classic volverá a descargar los paquetes desde el registro en futuras instalaciones.",
                regenerationEN: "Yarn Classic will re-download tarballs from the registry on next install.",
                isAvailable: true
            )

            return PackageManagerInspection(
                kind: .yarn,
                executablePath: yarnPath,
                versionString: parsedVer.version,
                majorVersion: parsedVer.major,
                variantLabel: "Yarn Classic (v1)",
                isInstalled: true,
                cachePaths: cachePaths,
                cacheAllocatedBytes: measured.allocatedBytes,
                cacheLogicalBytes: measured.logicalBytes,
                cacheMeasurementPartial: measured.isPartial,
                installedPackagesPaths: installedDirs,
                preservedSummaryES: preservedES,
                preservedSummaryEN: preservedEN,
                capabilities: [cleanCap]
            )
        } else {
            // Yarn Berry (v2-v4+): `yarn cache clean` alone acts on the local project `.yarn/cache`.
            // Global shared mirror cleanup uses `--mirror`.
            let globalRes = try? executor.run(
                CommandExecutionRequest(
                    executable: yarnPath,
                    arguments: ["config", "get", "globalFolder"],
                    timeout: 10,
                    directory: cwd,
                    extraPATHDirectories: [binDir],
                    environmentOverrides: env
                ),
                control: control
            )
            let globalFolderRaw = globalRes?.status == 0
                ? globalRes?.output.split(separator: "\n").last?.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil
            let globalFolder = (globalFolderRaw?.nonEmpty).map(Paths.normalized) ?? Paths.normalized(home + "/.yarn/berry")
            let berryCacheDir = Paths.normalized(globalFolder + "/cache")
            let existingCachePaths = PackageManagerInspectionHelpers.existingPaths([berryCacheDir, globalFolder])
            let targetPaths = existingCachePaths.isEmpty ? [berryCacheDir] : [existingCachePaths[0]]
            let measured = PackageManagerInspectionHelpers.measureDirectories(
                targetPaths,
                home: home,
                readPolicy: readPolicy,
                control: control
            )

            let mirrorCap = PackageManagerOperationCapability(
                id: "yarn.berry.cache.clean.mirror",
                kind: .yarn,
                titleES: "Vaciar la caché global espejo de Yarn Berry (v\(parsedVer.major))",
                titleEN: "Clean Yarn Berry (v\(parsedVer.major)) global mirror cache",
                descriptionES: "Alcance completo del espejo global: ejecuta yarn cache clean --mirror sin tocar cachés locales .yarn/cache (Zero-Installs) dentro de tus proyectos.",
                descriptionEN: "Full global mirror scope: runs yarn cache clean --mirror while keeping per-project .yarn/cache Zero-Installs untouched.",
                commandPreview: "yarn cache clean --mirror",
                executable: yarnPath,
                arguments: ["cache", "clean", "--mirror"],
                environmentOverrides: env,
                scope: .entireCache,
                measuredCacheBytes: measured.allocatedBytes,
                estimatedReclaimableBytes: measured.allocatedBytes,
                sizeBasis: measured.allocatedBytes != nil ? .measured : .estimated,
                preservedSummaryES: preservedES + " También conserva las cachés locales .yarn/cache de cada repositorio.",
                preservedSummaryEN: preservedEN + " Per-repository local .yarn/cache folders are also kept.",
                regenerationES: "Yarn Berry volverá a poblar el espejo global al ejecutar yarn install.",
                regenerationEN: "Yarn Berry will repopulate the global mirror on future yarn install runs.",
                isAvailable: true
            )

            return PackageManagerInspection(
                kind: .yarn,
                executablePath: yarnPath,
                versionString: parsedVer.version,
                majorVersion: parsedVer.major,
                variantLabel: "Yarn Berry (v\(parsedVer.major))",
                isInstalled: true,
                cachePaths: targetPaths,
                cacheAllocatedBytes: measured.allocatedBytes,
                cacheLogicalBytes: measured.logicalBytes,
                cacheMeasurementPartial: measured.isPartial,
                installedPackagesPaths: installedDirs,
                preservedSummaryES: preservedES,
                preservedSummaryEN: preservedEN,
                capabilities: [mirrorCap]
            )
        }
    }
}

// MARK: - Plan & Execution Coordinator

public final class PackageManagerService: @unchecked Sendable {
    private let executor: CommandExecuting
    private let journal: Journal
    private let home: String
    private let readPolicy: ReadAuthorizationPolicy
    private let adapters: [any PackageManagerAdapter]
    private let lock = NSLock()

    public init(
        journal: Journal,
        home: String = NSHomeDirectory(),
        readPolicy: ReadAuthorizationPolicy? = nil,
        executor: CommandExecuting = LiveCommandExecutor(),
        adapters: [any PackageManagerAdapter]? = nil
    ) {
        let normHome = Paths.normalized(home)
        let pol = readPolicy ?? ReadAuthorizationPolicy(home: normHome)
        self.executor = executor
        self.journal = journal
        self.home = normHome
        self.readPolicy = pol
        self.adapters = adapters ?? [
            HomebrewAdapter(executor: executor, home: normHome, readPolicy: pol),
            NpmAdapter(executor: executor, home: normHome, readPolicy: pol),
            PnpmAdapter(executor: executor, home: normHome, readPolicy: pol),
            YarnAdapter(executor: executor, home: normHome, readPolicy: pol)
        ]
    }

    public func inspectAll(control: ScanControl = ScanControl()) -> [PackageManagerInspection] {
        BoundedConcurrency.mapOrdered(adapters, maxConcurrent: 4, control: control) { adapter in
            adapter.inspect(control: control)
        }.compactMap { $0 }
    }

    public func buildPlan(
        inspection: PackageManagerInspection,
        capability: PackageManagerOperationCapability
    ) -> OperationPlan {
        var blockers: [OperationBlocker] = []
        if !inspection.isInstalled || inspection.executablePath == nil {
            blockers.append(OperationBlocker(
                reasonES: "\(inspection.displayName) no está instalado en este Mac.",
                reasonEN: "\(inspection.displayName) is not installed on this Mac."
            ))
        }
        if !capability.isAvailable {
            blockers.append(OperationBlocker(
                reasonES: capability.unavailableReasonES ?? "Capacidad no disponible para esta versión.",
                reasonEN: capability.unavailableReasonEN ?? "Capability unavailable for this version."
            ))
        }
        if capability.scope == .unsupportedForGlobalCleanup {
            blockers.append(OperationBlocker(
                reasonES: "La versión o configuración actual no admite limpieza global segura.",
                reasonEN: "Current version or setup does not expose safe global cache cleanup."
            ))
        }

        let estimated = capability.estimatedReclaimableBytes ?? capability.measuredCacheBytes
        let cacheList = inspection.cachePaths.joined(separator: ", ")
        let resource = OperationAffectedResource(
            id: capability.id,
            labelES: "\(inspection.displayName): \(capability.titleES)",
            labelEN: "\(inspection.displayName): \(capability.titleEN)",
            pathOrIdentifier: cacheList.isEmpty ? capability.commandPreview : cacheList,
            sizeBytes: estimated,
            logicalBytes: inspection.cacheLogicalBytes,
            sizeBasis: capability.sizeBasis,
            mechanism: .toolCommand,
            blockedReasonES: blockers.first?.reasonES,
            blockedReasonEN: blockers.first?.reasonEN
        )

        let scopeES: String
        let scopeEN: String
        switch capability.scope {
        case .entireCache:
            scopeES = "Alcance completo: \(capability.commandPreview) vacía toda la caché reportada (\(cacheList)). No es posible excluir elementos individuales."
            scopeEN = "Entire cache scope: \(capability.commandPreview) clears the whole cache at \(cacheList). Individual entries cannot be selectively excluded."
        case .unreferencedAndOutdated:
            scopeES = "Alcance selectivo del gestor: \(capability.commandPreview) limpia solo elementos obsoletos o sin referencia dentro de \(cacheList)."
            scopeEN = "Tool-managed selective scope: \(capability.commandPreview) removes only outdated or unreferenced entries inside \(cacheList)."
        case .unsupportedForGlobalCleanup:
            scopeES = "Sin soporte seguro para limpieza global."
            scopeEN = "Unsupported for global cleanup."
        }

        return OperationPlan(
            domain: .packageManagers,
            titleES: "\(inspection.displayName) · \(capability.titleES)",
            titleEN: "\(inspection.displayName) · \(capability.titleEN)",
            scopeDescriptionES: scopeES,
            scopeDescriptionEN: scopeEN,
            affectedResources: [resource],
            preservedSummaryES: capability.preservedSummaryES,
            preservedSummaryEN: capability.preservedSummaryEN,
            totalBytes: estimated,
            logicalBytes: inspection.cacheLogicalBytes,
            sizeBasis: capability.sizeBasis,
            sizeNoteES: capability.sizeBasis == .measured
                ? "Tamaño total medido de la caché en disco (\(cacheList))."
                : "Tamaño estimado a partir del estado o dry-run de \(inspection.displayName); el ahorro real se medirá tras la ejecución.",
            sizeNoteEN: capability.sizeBasis == .measured
                ? "Measured on-disk cache size (\(cacheList))."
                : "Estimated from \(inspection.displayName) inspection/dry-run; actual reclaimed delta is measured after execution.",
            regenerationES: capability.regenerationES,
            regenerationEN: capability.regenerationEN,
            mechanism: .toolCommand,
            restorability: .irreversible,
            restorabilityNoteES: "La limpieza se ejecuta mediante el comando oficial de \(inspection.displayName) (\(capability.commandPreview)), no mediante Papelera. No admite deshacer.",
            restorabilityNoteEN: "Cleanup runs via \(inspection.displayName)'s official CLI (\(capability.commandPreview)), not macOS Trash. Cannot be undone from Trash.",
            blockers: blockers,
            canExecute: blockers.isEmpty
        )
    }

    public func execute(
        plan: OperationPlan,
        inspection: PackageManagerInspection,
        capability: PackageManagerOperationCapability,
        timeout: TimeInterval = 90,
        cancellation: CancellationFlag = CancellationFlag()
    ) throws -> OperationExecutionReport {
        guard lock.try() else {
            throw BrisaError.rejected("Another package manager cleanup is already running")
        }
        defer { lock.unlock() }
        guard plan.domain == .packageManagers, plan.canExecute else {
            throw BrisaError.rejected("Package manager cleanup plan cannot execute")
        }

        _ = try journal.entries()
        let planEntry = try OperationJournalRecorder.recordPlan(plan, journal: journal, home: home)

        if cancellation.isCancelled {
            let final = try OperationJournalRecorder.finalizePlan(
                plan,
                planEntry: planEntry,
                outcome: .cancelled,
                completedCount: 0,
                skippedOrFailedCount: 1,
                detailNote: "Cancelled prior to invoking \(capability.commandPreview).",
                detailNoteES: "Cancelado antes de ejecutar \(capability.commandPreview).",
                restorable: false,
                journal: journal,
                home: home
            )
            return OperationExecutionReport(
                planID: plan.id,
                domain: .packageManagers,
                outcome: .cancelled,
                mechanism: .toolCommand,
                restorable: false,
                skippedOnCancellation: [capability.commandPreview],
                summaryES: "Operación cancelada antes de ejecutar \(capability.commandPreview).",
                summaryEN: "Cancelled before running \(capability.commandPreview).",
                journalEntries: [final]
            )
        }

        let beforeMeasure = PackageManagerInspectionHelpers.measureDirectories(
            inspection.cachePaths,
            home: home,
            readPolicy: readPolicy,
            control: ScanControl(cancellation: cancellation)
        )

        let execDir = URL(fileURLWithPath: capability.executable).deletingLastPathComponent().path
        let req = CommandExecutionRequest(
            executable: capability.executable,
            arguments: capability.arguments,
            timeout: timeout,
            directory: URL(fileURLWithPath: home, isDirectory: true),
            extraPATHDirectories: [execDir],
            environmentOverrides: capability.environmentOverrides
        )

        do {
            let res = try executor.run(req, control: ScanControl(cancellation: cancellation))
            let combinedOutput = [res.output, res.error]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            if cancellation.isCancelled {
                let final = try OperationJournalRecorder.finalizePlan(
                    plan,
                    planEntry: planEntry,
                    outcome: .cancelled,
                    completedCount: 0,
                    skippedOrFailedCount: 1,
                    errorText: "Cancelled during execution",
                    detailNote: "Cancelled while running \(capability.commandPreview).",
                    detailNoteES: "Operación cancelada durante \(capability.commandPreview).",
                    restorable: false,
                    journal: journal,
                    home: home
                )
                return OperationExecutionReport(
                    planID: plan.id,
                    domain: .packageManagers,
                    outcome: .cancelled,
                    mechanism: .toolCommand,
                    restorable: false,
                    skippedOnCancellation: [capability.commandPreview],
                    summaryES: "Operación cancelada durante \(capability.commandPreview).",
                    summaryEN: "Cancelled while running \(capability.commandPreview).",
                    commandOutput: combinedOutput.nonEmpty,
                    journalEntries: [final]
                )
            }

            if res.timedOut || res.status != 0 {
                let errMsg = res.timedOut
                    ? "Command timed out after \(Int(timeout))s"
                    : (res.error.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                        ?? "Exit status \(res.status)")
                let final = try OperationJournalRecorder.finalizePlan(
                    plan,
                    planEntry: planEntry,
                    outcome: .failed,
                    completedCount: 0,
                    skippedOrFailedCount: 1,
                    errorText: errMsg,
                    detailNote: "\(capability.commandPreview) failed: \(errMsg)",
                    detailNoteES: "Falló \(capability.commandPreview): \(errMsg)",
                    restorable: false,
                    journal: journal,
                    home: home
                )
                return OperationExecutionReport(
                    planID: plan.id,
                    domain: .packageManagers,
                    outcome: .failed,
                    mechanism: .toolCommand,
                    restorable: false,
                    failedItems: [capability.commandPreview],
                    summaryES: "Falló \(capability.commandPreview): \(errMsg)",
                    summaryEN: "\(capability.commandPreview) failed: \(errMsg)",
                    commandOutput: combinedOutput.nonEmpty,
                    journalEntries: [final]
                )
            }

            let afterMeasure = PackageManagerInspectionHelpers.measureDirectories(
                inspection.cachePaths,
                home: home,
                readPolicy: readPolicy,
                control: ScanControl()
            )
            let beforeBytes = beforeMeasure.allocatedBytes ?? capability.measuredCacheBytes
            let afterBytes = afterMeasure.allocatedBytes ?? 0
            let reclaimed = beforeBytes.map { max(0, $0 - afterBytes) } ?? capability.estimatedReclaimableBytes

            let final = try OperationJournalRecorder.finalizePlan(
                plan,
                planEntry: planEntry,
                outcome: .completed,
                completedCount: 1,
                skippedOrFailedCount: 0,
                detailNote: "Executed \(capability.commandPreview). Restorable: false.",
                detailNoteES: "Ejecutado \(capability.commandPreview). Sin restauración automática.",
                restorable: false,
                journal: journal,
                home: home
            )

            return OperationExecutionReport(
                planID: plan.id,
                domain: .packageManagers,
                outcome: .completed,
                mechanism: .toolCommand,
                restorable: false,
                completedItems: [capability.commandPreview],
                reclaimedBytesEstimate: reclaimed,
                summaryES: "Completado \(capability.commandPreview)" + (reclaimed.map { " · recuperado aprox. \(Formatting.bytes($0))." } ?? "."),
                summaryEN: "Completed \(capability.commandPreview)" + (reclaimed.map { " · reclaimed approx. \(Formatting.bytes($0))." } ?? "."),
                commandOutput: combinedOutput.nonEmpty,
                journalEntries: [final]
            )
        } catch {
            let outcome: OperationOutcomeStatus = cancellation.isCancelled ? .cancelled : .failed
            let final = try OperationJournalRecorder.finalizePlan(
                plan,
                planEntry: planEntry,
                outcome: outcome,
                completedCount: 0,
                skippedOrFailedCount: 1,
                errorText: error.localizedDescription,
                detailNote: error.localizedDescription,
                restorable: false,
                journal: journal,
                home: home
            )
            return OperationExecutionReport(
                planID: plan.id,
                domain: .packageManagers,
                outcome: outcome,
                mechanism: .toolCommand,
                restorable: false,
                failedItems: outcome == .failed ? [capability.commandPreview] : [],
                skippedOnCancellation: outcome == .cancelled ? [capability.commandPreview] : [],
                summaryES: "No se pudo ejecutar \(capability.commandPreview): \(error.localizedDescription)",
                summaryEN: "Could not execute \(capability.commandPreview): \(error.localizedDescription)",
                journalEntries: [final]
            )
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
