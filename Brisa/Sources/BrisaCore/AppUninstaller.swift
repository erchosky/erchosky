import Foundation
import Darwin
import Security
#if canImport(AppKit)
import AppKit
#endif

/// Confidence classification explaining why a file or directory was associated with an app.
public enum AppMatchConfidence: String, Codable, Equatable, Sendable {
    case highBundleID = "high_bundle_id"
    case mediumTeamOrGroup = "medium_team_or_group"
    case lowNameOnly = "low_name_only"
}

/// Separation tier between exclusive app data, potentially shared data, and uncertain matches.
public enum AppAssociationTier: String, Codable, Equatable, Sendable {
    case exclusiveData = "exclusive_data"
    case possibleShared = "possible_shared"
    case uncertainMatch = "uncertain_match"
}

/// Running process descriptor used to block uninstall safely until the user quits the app.
public struct RunningAppProcessInfo: Codable, Equatable, Sendable, Identifiable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let processName: String
    public let bundleIdentifier: String?

    public init(pid: Int32, processName: String, bundleIdentifier: String? = nil) {
        self.pid = pid
        self.processName = processName
        self.bundleIdentifier = bundleIdentifier
    }
}

/// Protocol abstracting live running-application inspection so unit tests remain deterministic.
public protocol AppRunningChecking: Sendable {
    func runningProcesses(for app: InstalledAppDescriptor) -> [RunningAppProcessInfo]
}

/// Live macOS running-application checker inspecting `NSWorkspace` and processes executing inside the bundle.
public struct LiveAppRunningChecker: AppRunningChecking {
    public init() {}

    public func runningProcesses(for app: InstalledAppDescriptor) -> [RunningAppProcessInfo] {
        var found: [Int32: RunningAppProcessInfo] = [:]
        let normBundle = Paths.normalized(app.bundlePath)

        #if canImport(AppKit)
        for running in NSWorkspace.shared.runningApplications {
            let matchBundleID = (app.bundleID != nil && running.bundleIdentifier == app.bundleID)
            let matchURL = running.bundleURL.map { Paths.normalized($0.path) == normBundle } ?? false
            if matchBundleID || matchURL {
                let pid = running.processIdentifier
                found[pid] = RunningAppProcessInfo(
                    pid: pid,
                    processName: running.localizedName ?? app.name,
                    bundleIdentifier: running.bundleIdentifier
                )
            }
        }
        #endif

        if let processes = try? ProcessInspector.list() {
            let prefix = normBundle + "/"
            for proc in processes {
                let exec = Paths.normalized(proc.executable)
                if exec.hasPrefix(prefix) && found[proc.id] == nil {
                    found[proc.id] = RunningAppProcessInfo(
                        pid: proc.id,
                        processName: URL(fileURLWithPath: exec).lastPathComponent,
                        bundleIdentifier: app.bundleID
                    )
                }
            }
        }

        return found.values.sorted { $0.pid < $1.pid }
    }
}

/// Verified identity, signing, protection, and privilege metadata for a discovered `.app` bundle.
public struct InstalledAppDescriptor: Codable, Equatable, Sendable, Identifiable {
    public var id: String { bundlePath }
    public let bundlePath: String
    public let name: String
    public let bundleID: String?
    public let shortVersion: String?
    public let teamID: String?
    public let signingIdentifier: String?
    public let appGroupIDs: [String]
    public let isSystemProtected: Bool
    public let systemProtectionReasonES: String?
    public let systemProtectionReasonEN: String?
    public let requiresPrivilegesToTrash: Bool
    public let privilegeReasonES: String?
    public let privilegeReasonEN: String?
    public let allocatedBytes: Int64
    public let logicalBytes: Int64
    public let identity: FileIdentity?

    public init(
        bundlePath: String,
        name: String,
        bundleID: String?,
        shortVersion: String? = nil,
        teamID: String? = nil,
        signingIdentifier: String? = nil,
        appGroupIDs: [String] = [],
        isSystemProtected: Bool = false,
        systemProtectionReasonES: String? = nil,
        systemProtectionReasonEN: String? = nil,
        requiresPrivilegesToTrash: Bool = false,
        privilegeReasonES: String? = nil,
        privilegeReasonEN: String? = nil,
        allocatedBytes: Int64 = 0,
        logicalBytes: Int64 = 0,
        identity: FileIdentity? = nil
    ) {
        self.bundlePath = Paths.normalized(bundlePath)
        self.name = name
        self.bundleID = bundleID
        self.shortVersion = shortVersion
        self.teamID = teamID
        self.signingIdentifier = signingIdentifier
        self.appGroupIDs = appGroupIDs
        self.isSystemProtected = isSystemProtected
        self.systemProtectionReasonES = systemProtectionReasonES
        self.systemProtectionReasonEN = systemProtectionReasonEN
        self.requiresPrivilegesToTrash = requiresPrivilegesToTrash
        self.privilegeReasonES = privilegeReasonES
        self.privilegeReasonEN = privilegeReasonEN
        self.allocatedBytes = allocatedBytes
        self.logicalBytes = logicalBytes
        self.identity = identity
    }
}

/// Related leftover/support/cache/container artifact discovered for an installed application.
public struct AppRelatedItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let displayName: String
    public let locationKind: String
    public let tier: AppAssociationTier
    public let confidence: AppMatchConfidence
    public let reasonES: String
    public let reasonEN: String
    public let sharedWithApps: [String]
    public let requiresPrivileges: Bool
    public let privilegeNoteES: String?
    public let privilegeNoteEN: String?
    public let defaultSelected: Bool
    public let allocatedBytes: Int64
    public let logicalBytes: Int64
    public let identity: FileIdentity?
}

/// Complete uninstaller audit report for a selected application.
public struct AppUninstallInspection: Codable, Equatable, Sendable {
    public let app: InstalledAppDescriptor
    public let runningProcesses: [RunningAppProcessInfo]
    public let relatedItems: [AppRelatedItem]

    public var isRunning: Bool { !runningProcesses.isEmpty }
    public var exclusiveItems: [AppRelatedItem] { relatedItems.filter { $0.tier == .exclusiveData } }
    public var possibleSharedItems: [AppRelatedItem] { relatedItems.filter { $0.tier == .possibleShared } }
    public var uncertainItems: [AppRelatedItem] { relatedItems.filter { $0.tier == .uncertainMatch } }
    public var privilegedPendingItems: [AppRelatedItem] {
        relatedItems.filter { $0.requiresPrivileges }
    }
}

/// Discovers verifiable app identity, related artifacts, shared-data collisions, running locks, and executes Trash uninstall.
public final class AppUninstaller: @unchecked Sendable {
    private static let genericNamesForFuzzySkip: Set<String> = [
        "app", "helper", "agent", "service", "mail", "notes", "music", "photos",
        "messages", "calendar", "safari", "finder", "preview", "system", "apple",
        "files", "downloads", "documents", "desktop", "code", "terminal"
    ]

    private let home: String
    private let systemRoots: [String]
    private let protectedPaths: [String]
    private let readPolicy: ReadAuthorizationPolicy
    private let runningChecker: AppRunningChecking
    private let journal: Journal
    private let mover: TrashMoving
    private let selfBundleIdentifier: String?
    private let selfBundlePath: String?
    private let lock = NSLock()
    private var peerDescriptorCache: [String: (identity: FileIdentity, descriptor: InstalledAppDescriptor)] = [:]

    public init(
        journal: Journal,
        home: String = NSHomeDirectory(),
        systemRoots: [String] = ["/Library"],
        protectedPaths: [String] = [],
        readPolicy: ReadAuthorizationPolicy? = nil,
        runningChecker: AppRunningChecking = LiveAppRunningChecker(),
        mover: TrashMoving = SystemTrashMover(),
        selfBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        selfBundlePath: String? = Bundle.main.bundlePath
    ) {
        self.home = Paths.normalized(home)
        self.systemRoots = systemRoots.map(Paths.normalized)
        self.protectedPaths = protectedPaths.map(Paths.normalized)
        self.readPolicy = readPolicy ?? ReadAuthorizationPolicy(home: self.home, protectedPaths: self.protectedPaths, allowSystemLocations: true)
        self.runningChecker = runningChecker
        self.journal = journal
        self.mover = mover
        self.selfBundleIdentifier = selfBundleIdentifier
        self.selfBundlePath = selfBundlePath.map(Paths.normalized)
    }

    /// Reads Info.plist and static code signing metadata (`TeamIdentifier`, entitlements) without executing the bundle.
    public func describeApplication(at rawBundlePath: String, measureBundleSize: Bool = true) -> InstalledAppDescriptor {
        let bundlePath = Paths.normalized(rawBundlePath)
        let bundleURL = URL(fileURLWithPath: bundlePath, isDirectory: true)
        let bundle = Bundle(url: bundleURL)
        let info = bundle?.infoDictionary
        let bundleID = (info?["CFBundleIdentifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let displayName = (info?["CFBundleDisplayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? (info?["CFBundleName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? bundleURL.deletingPathExtension().lastPathComponent
        let shortVersion = (info?["CFBundleShortVersionString"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        var teamID: String?
        var signingID: String?
        var appGroups: [String] = []
        var staticCode: SecStaticCode?
        if SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess,
           let staticCode {
            var infoDict: CFDictionary?
            if SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &infoDict) == errSecSuccess,
               let dict = infoDict as? [String: Any] {
                teamID = (dict[kSecCodeInfoTeamIdentifier as String] as? String)?.nilIfEmpty
                signingID = (dict[kSecCodeInfoIdentifier as String] as? String)?.nilIfEmpty
                if let ent = dict[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
                   let groups = ent["com.apple.security.application-groups"] as? [String] {
                    appGroups = groups
                }
            }
        }

        // Fallback test/bundle Info.plist group declaration if unsigned
        if appGroups.isEmpty, let plistGroups = info?["BrisaAppGroups"] as? [String] {
            appGroups = plistGroups
        }

        var st = stat()
        let exists = lstat(bundlePath, &st) == 0
        let identity = exists ? SafetyPolicy.identity(st) : nil

        let (sysProtected, sysES, sysEN) = evaluateSystemProtection(bundlePath: bundlePath, bundleID: bundleID)
        let (needsPriv, privES, privEN) = evaluatePrivilegeRequirement(for: bundlePath, isAppBundle: true)

        var allocated: Int64 = 0
        var logical: Int64 = 0
        if measureBundleSize && exists && (st.st_mode & S_IFMT) == S_IFDIR {
            var seen = Set<InodeKey>()
            var examined = 0
            if let measured = StorageMeasurement.measure(
                path: bundlePath,
                category: .appLeftovers,
                readPolicy: ReadAuthorizationPolicy(home: home, projectRoots: [bundleURL.deletingLastPathComponent().path], allowSystemLocations: true),
                claimedPaths: [],
                neverTouchedPaths: [],
                seenInodes: &seen,
                cancellation: CancellationFlag(),
                maxEntriesPerItem: 60_000,
                examinedCounter: &examined
            ) {
                allocated = measured.allocatedBytes
                logical = measured.logicalBytes
            }
        }

        return InstalledAppDescriptor(
            bundlePath: bundlePath,
            name: displayName,
            bundleID: bundleID,
            shortVersion: shortVersion,
            teamID: teamID,
            signingIdentifier: signingID,
            appGroupIDs: appGroups,
            isSystemProtected: sysProtected,
            systemProtectionReasonES: sysES,
            systemProtectionReasonEN: sysEN,
            requiresPrivilegesToTrash: needsPriv,
            privilegeReasonES: privES,
            privilegeReasonEN: privEN,
            allocatedBytes: allocated,
            logicalBytes: logical,
            identity: identity
        )
    }

    public func inspect(
        appBundlePath: String,
        otherInstalledAppPaths: [String] = []
    ) -> AppUninstallInspection {
        let descriptor = describeApplication(at: appBundlePath, measureBundleSize: true)
        let peers = describePeerApplications(otherInstalledAppPaths, excluding: descriptor.bundlePath)

        let running = runningChecker.runningProcesses(for: descriptor)
        let related = discoverRelatedItems(for: descriptor, peerApps: peers)
        return AppUninstallInspection(app: descriptor, runningProcesses: running, relatedItems: related)
    }

    private func describePeerApplications(_ rawPaths: [String], excluding targetBundlePath: String) -> [InstalledAppDescriptor] {
        var uniquePaths: [String] = []
        var seen = Set<String>()
        for raw in rawPaths {
            let norm = Paths.normalized(raw)
            guard norm != targetBundlePath, seen.insert(norm).inserted else { continue }
            uniquePaths.append(norm)
        }
        guard !uniquePaths.isEmpty else { return [] }

        var slots = Array<InstalledAppDescriptor?>(repeating: nil, count: uniquePaths.count)
        var coldIndices: [(index: Int, path: String, identity: FileIdentity?)] = []
        coldIndices.reserveCapacity(uniquePaths.count)

        for (idx, path) in uniquePaths.enumerated() {
            var st = stat()
            let currentIdentity: FileIdentity? = (lstat(path, &st) == 0) ? SafetyPolicy.identity(st) : nil
            if let currentIdentity,
               let cached = lock.withLock({ peerDescriptorCache[path] }),
               cached.identity == currentIdentity {
                slots[idx] = cached.descriptor
            } else {
                coldIndices.append((idx, path, currentIdentity))
            }
        }

        if !coldIndices.isEmpty {
            let described = BoundedConcurrency.mapOrdered(coldIndices, maxConcurrent: 4) { item in
                (item, self.describeApplication(at: item.path, measureBundleSize: false))
            }.compactMap { $0 }

            for (item, desc) in described {
                slots[item.index] = desc
                if let identity = desc.identity ?? item.identity {
                    lock.withLock {
                        if peerDescriptorCache.count > 1024 {
                            peerDescriptorCache.removeAll(keepingCapacity: true)
                        }
                        peerDescriptorCache[item.path] = (identity: identity, descriptor: desc)
                    }
                }
            }
        }

        return slots.compactMap { $0 }
    }

    public func buildPlan(
        inspection: AppUninstallInspection,
        selectedItemIDs: Set<String>,
        includeAppBundle: Bool = true
    ) -> OperationPlan {
        let app = inspection.app
        var blockers: [OperationBlocker] = []
        var resources: [OperationAffectedResource] = []
        var totalAlloc: Int64 = 0
        var totalLog: Int64 = 0

        if app.isSystemProtected {
            blockers.append(OperationBlocker(
                resourceID: app.bundlePath,
                reasonES: app.systemProtectionReasonES ?? "Aplicación protegida del sistema.",
                reasonEN: app.systemProtectionReasonEN ?? "Protected system application."
            ))
        }

        if inspection.isRunning {
            let pids = inspection.runningProcesses.map { "\($0.processName) (\($0.pid))" }.joined(separator: ", ")
            blockers.append(OperationBlocker(
                resourceID: app.bundlePath,
                reasonES: "La aplicación está abierta (\(pids)). Ciérrala tú mismo y vuelve a comprobar antes de desinstalar.",
                reasonEN: "Application is currently running (\(pids)). Quit it manually and click Recheck before uninstalling.",
                canRecheck: true
            ))
        }

        if includeAppBundle {
            var appBlockES: String?
            var appBlockEN: String?
            if app.isSystemProtected {
                appBlockES = app.systemProtectionReasonES
                appBlockEN = app.systemProtectionReasonEN
            } else if inspection.isRunning {
                appBlockES = "La aplicación está abierta; ciérrala primero."
                appBlockEN = "App is running; quit it first."
            } else if app.requiresPrivilegesToTrash {
                appBlockES = app.privilegeReasonES ?? "Requiere privilegios de administrador para moverla desde su carpeta."
                appBlockEN = app.privilegeReasonEN ?? "Requires administrator privileges to move from its parent directory."
                blockers.append(OperationBlocker(
                    resourceID: app.bundlePath,
                    reasonES: appBlockES!,
                    reasonEN: appBlockEN!
                ))
            } else if Paths.containsAncestor(of: app.bundlePath, in: Set(protectedPaths)) {
                appBlockES = "La aplicación está en tus rutas protegidas."
                appBlockEN = "Application path is in your protected paths."
                blockers.append(OperationBlocker(
                    resourceID: app.bundlePath,
                    reasonES: appBlockES!,
                    reasonEN: appBlockEN!
                ))
            } else {
                totalAlloc = ByteTotals.adding(totalAlloc, app.allocatedBytes)
                totalLog = ByteTotals.adding(totalLog, app.logicalBytes)
            }

            resources.append(OperationAffectedResource(
                id: app.bundlePath,
                labelES: "\(app.name).app (paquete de aplicación)",
                labelEN: "\(app.name).app (application bundle)",
                pathOrIdentifier: app.bundlePath,
                sizeBytes: app.allocatedBytes,
                logicalBytes: app.logicalBytes,
                sizeBasis: .measured,
                mechanism: .trash,
                blockedReasonES: appBlockES,
                blockedReasonEN: appBlockEN
            ))
        }

        for item in inspection.relatedItems where selectedItemIDs.contains(item.id) {
            var itemBlockES: String?
            var itemBlockEN: String?

            if app.isSystemProtected || inspection.isRunning {
                itemBlockES = blockers.first?.reasonES ?? "Aplicación bloqueada."
                itemBlockEN = blockers.first?.reasonEN ?? "Application blocked."
            } else if item.requiresPrivileges {
                itemBlockES = item.privilegeNoteES ?? "Requiere privilegios elevados; queda pendiente para revisión manual."
                itemBlockEN = item.privilegeNoteEN ?? "Requires elevated privileges; left pending for manual review."
                blockers.append(OperationBlocker(
                    resourceID: item.id,
                    reasonES: itemBlockES!,
                    reasonEN: itemBlockEN!
                ))
            } else if !item.sharedWithApps.isEmpty {
                let apps = item.sharedWithApps.joined(separator: ", ")
                itemBlockES = "Compartido con otra(s) app(s) instalada(s): \(apps)."
                itemBlockEN = "Shared with other installed app(s): \(apps)."
                blockers.append(OperationBlocker(
                    resourceID: item.id,
                    reasonES: itemBlockES!,
                    reasonEN: itemBlockEN!
                ))
            } else if Paths.containsAncestor(of: item.path, in: Set(protectedPaths)) {
                itemBlockES = "Ruta marcada como protegida."
                itemBlockEN = "Path is marked as protected."
                blockers.append(OperationBlocker(
                    resourceID: item.id,
                    reasonES: itemBlockES!,
                    reasonEN: itemBlockEN!
                ))
            } else {
                totalAlloc = ByteTotals.adding(totalAlloc, item.allocatedBytes)
                totalLog = ByteTotals.adding(totalLog, item.logicalBytes)
            }

            resources.append(OperationAffectedResource(
                id: item.id,
                labelES: "\(item.locationKind): \(item.displayName)",
                labelEN: "\(item.locationKind): \(item.displayName)",
                pathOrIdentifier: item.path,
                sizeBytes: item.allocatedBytes,
                logicalBytes: item.logicalBytes,
                sizeBasis: .measured,
                mechanism: .trash,
                blockedReasonES: itemBlockES,
                blockedReasonEN: itemBlockEN
            ))
        }

        let actionable = resources.filter { !$0.isBlocked }
        let privilegedNotes = inspection.privilegedPendingItems.map(\.path)
        let sharedCount = inspection.possibleSharedItems.filter { !$0.sharedWithApps.isEmpty }.count

        var preservedPartsES: [String] = ["Tus documentos personales en Documentos, Escritorio y Descargas nunca se seleccionan ni eliminan."]
        var preservedPartsEN: [String] = ["User documents in Documents, Desktop, and Downloads are never selected or deleted."]
        if sharedCount > 0 {
            preservedPartsES.append("Se protegen \(sharedCount) elemento(s) potencialmente compartidos con otras apps instaladas.")
            preservedPartsEN.append("\(sharedCount) item(s) potentially shared with other installed apps remain protected.")
        }
        if !privilegedNotes.isEmpty {
            preservedPartsES.append("\(privilegedNotes.count) componente(s) que requieren privilegios quedan pendientes sin elevación general.")
            preservedPartsEN.append("\(privilegedNotes.count) privileged component(s) stay pending without general privilege elevation.")
        }

        let hasFatalAppBlocker = app.isSystemProtected || inspection.isRunning || (includeAppBundle && app.requiresPrivilegesToTrash)
        return OperationPlan(
            domain: .appUninstall,
            titleES: "Desinstalar \(app.name) mediante Papelera",
            titleEN: "Uninstall \(app.name) via Trash",
            scopeDescriptionES: "Solo se moverán a la Papelera los elementos verificables y compatibles seleccionados (\(actionable.count)). Nunca se cierran procesos automáticamente ni se elevan privilegios de sistema.",
            scopeDescriptionEN: "Only verified, user-writable selected items (\(actionable.count)) will move to Trash. Processes are never killed automatically and no general privilege elevation is used.",
            affectedResources: resources,
            preservedSummaryES: preservedPartsES.joined(separator: " "),
            preservedSummaryEN: preservedPartsEN.joined(separator: " "),
            totalBytes: totalAlloc,
            logicalBytes: totalLog,
            sizeBasis: .measured,
            sizeNoteES: "Espacio medido en disco de la app y componentes compatibles movibles sin privilegios.",
            sizeNoteEN: "Measured on-disk size for bundle and non-privileged Trash-compatible items.",
            regenerationES: "Puedes devolver los elementos desde la Papelera o reinstalar \(app.name) desde su instalador o App Store.",
            regenerationEN: "Put items back from macOS Trash or reinstall \(app.name) from its installer or App Store.",
            mechanism: .trash,
            restorability: .trashRestore,
            restorabilityNoteES: "Todos los elementos compatibles se envían a la Papelera de macOS para poder restaurarlos.",
            restorabilityNoteEN: "All compatible components are moved to macOS Trash and can be restored.",
            blockers: blockers,
            canExecute: !hasFatalAppBlocker && !actionable.isEmpty
        )
    }

    public func execute(
        plan: OperationPlan,
        inspection: AppUninstallInspection,
        cancellation: CancellationFlag = CancellationFlag()
    ) throws -> OperationExecutionReport {
        guard lock.try() else {
            throw BrisaError.rejected("Another uninstall operation is already running")
        }
        defer { lock.unlock() }
        guard plan.domain == .appUninstall, plan.canExecute else {
            throw BrisaError.rejected("App uninstall plan cannot execute")
        }

        _ = try journal.entries()
        let planEntry = try OperationJournalRecorder.recordPlan(plan, journal: journal, home: home)

        // Live revalidation of running processes before doing anything
        let liveRunning = runningChecker.runningProcesses(for: inspection.app)
        guard liveRunning.isEmpty else {
            let names = liveRunning.map { "\($0.processName) (\($0.pid))" }.joined(separator: ", ")
            let final = try OperationJournalRecorder.finalizePlan(
                plan,
                planEntry: planEntry,
                outcome: .rejected,
                completedCount: 0,
                skippedOrFailedCount: plan.actionableResources.count,
                errorText: "Application is running: \(names)",
                detailNote: "Blocked uninstall because app is running: \(names).",
                detailNoteES: "Desinstalación bloqueada porque la aplicación está en ejecución: \(names).",
                restorable: false,
                journal: journal,
                home: home
            )
            return OperationExecutionReport(
                planID: plan.id,
                domain: .appUninstall,
                outcome: .rejected,
                mechanism: .trash,
                restorable: false,
                rejectedItems: plan.actionableResources.map(\.pathOrIdentifier),
                summaryES: "\(inspection.app.name) sigue en ejecución (\(names)). Ciérrala y vuelve a comprobar.",
                summaryEN: "\(inspection.app.name) is still running (\(names)). Quit it and recheck.",
                journalEntries: [final]
            )
        }

        guard !inspection.app.isSystemProtected else {
            let final = try OperationJournalRecorder.finalizePlan(
                plan,
                planEntry: planEntry,
                outcome: .rejected,
                completedCount: 0,
                skippedOrFailedCount: plan.actionableResources.count,
                errorText: "System-protected application",
                detailNote: "Rejected uninstall of system-protected app.",
                detailNoteES: "Desinstalación rechazada por protección del sistema.",
                restorable: false,
                journal: journal,
                home: home
            )
            return OperationExecutionReport(
                planID: plan.id,
                domain: .appUninstall,
                outcome: .rejected,
                mechanism: .trash,
                restorable: false,
                rejectedItems: plan.actionableResources.map(\.pathOrIdentifier),
                summaryES: "Aplicación protegida del sistema; bloqueada.",
                summaryEN: "System-protected application; rejected.",
                journalEntries: [final]
            )
        }

        // Build lookup map of expected identities for revalidation
        var expectedIdentities: [String: FileIdentity] = [:]
        if let appID = inspection.app.identity {
            expectedIdentities[inspection.app.bundlePath] = appID
        }
        for item in inspection.relatedItems {
            if let id = item.identity {
                expectedIdentities[item.path] = id
            }
        }

        // Trash related support items BEFORE moving the `.app` bundle, or if cancelling stops early, `.app` isn't left broken without reason
        let orderedTargets = plan.actionableResources.sorted { lhs, rhs in
            if lhs.pathOrIdentifier == inspection.app.bundlePath { return false }
            if rhs.pathOrIdentifier == inspection.app.bundlePath { return true }
            return lhs.pathOrIdentifier < rhs.pathOrIdentifier
        }

        var completed: [String] = []
        var rejected: [String] = []
        var failed: [String] = []
        var skipped: [String] = []
        var entries: [JournalEntry] = [planEntry]
        var reclaimedBytes: Int64 = 0
        var cancelledDuringRun = false

        for (index, res) in orderedTargets.enumerated() {
            if cancellation.isCancelled {
                cancelledDuringRun = true
                skipped.append(contentsOf: orderedTargets[index...].map(\.pathOrIdentifier))
                break
            }

            // Recheck running state right before touching items
            if !runningChecker.runningProcesses(for: inspection.app).isEmpty {
                rejected.append(contentsOf: orderedTargets[index...].map(\.pathOrIdentifier))
                break
            }

            let targetPath = Paths.normalized(res.pathOrIdentifier)
            let freeBefore = OperationJournalRecorder.currentAvailableCapacity(for: home)
            var entry = JournalEntry(
                operation: targetPath == inspection.app.bundlePath ? "app_uninstall.bundle" : "app_uninstall.artifact",
                originalPath: targetPath,
                size: res.logicalBytes ?? 0,
                allocatedBytes: res.sizeBytes,
                identity: expectedIdentities[targetPath] ?? FileIdentity(device: 0, inode: 0, size: 0, modified: 0, changed: 0),
                status: "intent",
                freeSpaceBefore: freeBefore,
                domain: OperationDomain.appUninstall.rawValue,
                mechanism: OperationMechanism.trash.rawValue,
                restorable: false,
                planID: plan.id,
                summaryTitle: res.labelEN,
                summaryTitleES: res.labelES
            )

            guard !Paths.containsAncestor(of: targetPath, in: Set(protectedPaths)),
                  (try? SafetyPolicy.rejectSymlinks(targetPath)) != nil,
                  revalidateTargetBeforeTrash(path: targetPath, expectedIdentity: expectedIdentities[targetPath]) else {
                entry.status = OperationOutcomeStatus.rejected.rawValue
                entry.outcomeKind = OperationOutcomeStatus.rejected.rawValue
                entry.error = "Path modified, protected, symlinked, or requires privileges"
                entry.freeSpaceAfter = OperationJournalRecorder.currentAvailableCapacity(for: home)
                try journal.append(entry)
                entries.append(entry)
                rejected.append(targetPath)
                continue
            }

            do {
                try journal.append(entry)
                let trashURL = try mover.move(URL(fileURLWithPath: targetPath))
                entry.trashPath = trashURL?.path
                entry.status = "trashed"
                entry.outcomeKind = OperationOutcomeStatus.completed.rawValue
                entry.restorable = true
                entry.freeSpaceAfter = OperationJournalRecorder.currentAvailableCapacity(for: home)
                try journal.append(entry)
                entries.append(entry)
                completed.append(targetPath)
                reclaimedBytes = ByteTotals.adding(reclaimedBytes, res.sizeBytes ?? 0)
            } catch {
                entry.status = OperationOutcomeStatus.failed.rawValue
                entry.outcomeKind = OperationOutcomeStatus.failed.rawValue
                entry.error = error.localizedDescription
                entry.freeSpaceAfter = OperationJournalRecorder.currentAvailableCapacity(for: home)
                try journal.append(entry)
                entries.append(entry)
                failed.append(targetPath)
            }
        }

        let outcome = OperationJournalRecorder.resolveBatchOutcome(
            completed: completed.count,
            rejected: rejected.count,
            failed: failed.count,
            cancelled: cancelledDuringRun
        )
        let pendingPrivNote = inspection.privilegedPendingItems.isEmpty
            ? ""
            : " \(inspection.privilegedPendingItems.count) privileged component(s) remained untouched as pending."
        let pendingPrivNoteES = inspection.privilegedPendingItems.isEmpty
            ? ""
            : " \(inspection.privilegedPendingItems.count) componente(s) con privilegios permanecieron intactos como pendientes."
        let detail = (cancelledDuringRun && !completed.isEmpty
            ? "\(completed.count) moved to Trash; cancelled before \(skipped.count) remaining. Already trashed items were not rolled back."
            : "\(completed.count) completed, \(rejected.count) rejected, \(failed.count) failed.") + pendingPrivNote
        let detailES = (cancelledDuringRun && !completed.isEmpty
            ? "\(completed.count) enviado(s) a Papelera; cancelado antes de \(skipped.count) restante(s). Lo ya movido no se revirtió."
            : "\(completed.count) completado(s), \(rejected.count) rechazado(s), \(failed.count) fallido(s).") + pendingPrivNoteES

        let finalEntry = try OperationJournalRecorder.finalizePlan(
            plan,
            planEntry: planEntry,
            outcome: outcome,
            completedCount: completed.count,
            skippedOrFailedCount: rejected.count + failed.count + skipped.count,
            detailNote: detail,
            detailNoteES: detailES,
            restorable: !completed.isEmpty,
            journal: journal,
            home: home
        )
        entries[0] = finalEntry

        let summaryES: String
        let summaryEN: String
        switch outcome {
        case .completed:
            summaryES = "\(inspection.app.name) y \(max(0, completed.count - 1)) elemento(s) asociados enviados a la Papelera."
            summaryEN = "Moved \(inspection.app.name) and \(max(0, completed.count - 1)) related item(s) to Trash."
        case .partial:
            summaryES = "Desinstalación parcial: \(completed.count) enviado(s) a Papelera, \(rejected.count + failed.count + skipped.count) omitido(s)/pendiente(s). Lo enviado a Papelera no se revirtió."
            summaryEN = "Partial uninstall: \(completed.count) moved to Trash, \(rejected.count + failed.count + skipped.count) skipped/pending. Trashed items were not rolled back."
        case .cancelled:
            summaryES = "Desinstalación cancelada."
            summaryEN = "Uninstall cancelled."
        case .rejected:
            summaryES = "La desinstalación fue bloqueada al revalidar las rutas o el estado en ejecución."
            summaryEN = "Uninstall was rejected during live path or running-app revalidation."
        case .failed, .planned:
            summaryES = "La desinstalación falló al mover archivos a la Papelera."
            summaryEN = "Uninstall failed while moving items to Trash."
        }

        return OperationExecutionReport(
            planID: plan.id,
            domain: .appUninstall,
            outcome: outcome,
            mechanism: .trash,
            restorable: !completed.isEmpty,
            completedItems: completed,
            rejectedItems: rejected,
            failedItems: failed,
            skippedOnCancellation: skipped,
            reclaimedBytesEstimate: reclaimedBytes,
            summaryES: summaryES,
            summaryEN: summaryEN,
            journalEntries: entries
        )
    }

    // MARK: - Private Helpers

    private func evaluateSystemProtection(bundlePath: String, bundleID: String?) -> (Bool, String?, String?) {
        if let selfID = selfBundleIdentifier, let bundleID, bundleID == selfID {
            return (true, "Brisa está ejecutándose ahora mismo y está protegida.", "Brisa itself is protected.")
        }
        if let selfPath = selfBundlePath, bundlePath == selfPath {
            return (true, "No puedes desinstalar la propia aplicación Brisa.", "Cannot uninstall Brisa itself.")
        }
        if SafetyPolicy.within(bundlePath, "/System") || SafetyPolicy.within(bundlePath, "/Library/Apple") {
            return (true, "Aplicación del sistema protegida por macOS / SIP.", "macOS / SIP protected system application.")
        }
        if let bundleID, bundleID.hasPrefix("com.apple.") {
            // Protect Apple core bundles everywhere under /Applications or /System
            if SafetyPolicy.within(bundlePath, "/Applications") || SafetyPolicy.within(bundlePath, "/System") {
                return (true, "Aplicación de Apple protegida (\(bundleID)).", "Apple system/first-party application (\(bundleID)).")
            }
        }
        return (false, nil, nil)
    }

    private func evaluatePrivilegeRequirement(for path: String, isAppBundle: Bool) -> (Bool, String?, String?) {
        var st = stat()
        guard lstat(path, &st) == 0 else {
            return (false, nil, nil)
        }
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        var parentSt = stat()
        _ = lstat(parent, &parentSt)

        if st.st_uid != getuid() {
            return (
                true,
                "Propiedad de administrador/sistema; mover o borrar requiere privilegios elevados.",
                "Owned by root/another user; moving or removing requires elevated privileges."
            )
        }
        if access(parent, W_OK) != 0 {
            return (
                true,
                isAppBundle
                    ? "La carpeta contenedora no permite escritura con tu usuario actual; requiere permiso de administrador."
                    : "La ubicación requiere privilegios de administrador.",
                isAppBundle
                    ? "Parent directory is not writable by current user; requires admin permission."
                    : "Parent location requires administrator privileges."
            )
        }
        return (false, nil, nil)
    }

    private func discoverRelatedItems(
        for app: InstalledAppDescriptor,
        peerApps: [InstalledAppDescriptor]
    ) -> [AppRelatedItem] {
        var discovered: [String: AppRelatedItem] = [:]
        let fm = FileManager.default
        let libraryRoot = Paths.normalized(home + "/Library")

        func registerCandidate(
            path rawPath: String,
            locationKind: String,
            tier: AppAssociationTier,
            confidence: AppMatchConfidence,
            reasonES: String,
            reasonEN: String,
            sharedWithApps: [String] = [],
            forcePrivileged: Bool = false
        ) {
            let path = Paths.normalized(rawPath)
            guard discovered[path] == nil else { return }
            guard (try? SafetyPolicy.rejectSymlinks(path)) != nil else { return }
            var st = stat()
            guard lstat(path, &st) == 0 else { return }
            let mode = st.st_mode & S_IFMT
            guard mode == S_IFREG || mode == S_IFDIR else { return }
            guard !SafetyPolicy.within(path, home + "/Documents"),
                  !SafetyPolicy.within(path, home + "/Desktop"),
                  !SafetyPolicy.within(path, home + "/Downloads") else {
                return
            }

            let (needsPriv, privES, privEN) = forcePrivileged
                ? (true, "Ubicación global del sistema (/Library); requiere privilegios para eliminar.", "System-wide /Library location; requires privileges to remove.")
                : evaluatePrivilegeRequirement(for: path, isAppBundle: false)

            var alloc: Int64 = Int64(st.st_blocks) * 512
            var logical: Int64 = Int64(st.st_size)
            if mode == S_IFDIR {
                var seen = Set<InodeKey>()
                var examined = 0
                if let m = StorageMeasurement.measure(
                    path: path,
                    category: .appLeftovers,
                    readPolicy: ReadAuthorizationPolicy(home: home, projectRoots: [URL(fileURLWithPath: path).deletingLastPathComponent().path], allowSystemLocations: true),
                    claimedPaths: [],
                    neverTouchedPaths: [],
                    seenInodes: &seen,
                    cancellation: CancellationFlag(),
                    maxEntriesPerItem: 40_000,
                    examinedCounter: &examined
                ) {
                    alloc = m.allocatedBytes
                    logical = m.logicalBytes
                }
            }

            let autoSelect = (tier == .exclusiveData) && !needsPriv && sharedWithApps.isEmpty
            discovered[path] = AppRelatedItem(
                path: path,
                displayName: URL(fileURLWithPath: path).lastPathComponent,
                locationKind: locationKind,
                tier: tier,
                confidence: confidence,
                reasonES: reasonES,
                reasonEN: reasonEN,
                sharedWithApps: sharedWithApps,
                requiresPrivileges: needsPriv,
                privilegeNoteES: privES,
                privilegeNoteEN: privEN,
                defaultSelected: autoSelect,
                allocatedBytes: alloc,
                logicalBytes: logical,
                identity: SafetyPolicy.identity(st)
            )
        }

        // 1. Exact bundle-ID matches in user ~/Library locations
        if let bundleID = app.bundleID {
            let sharedByExactIDPeers = peerApps.filter { $0.bundleID == bundleID }.map(\.name)
            let tierForExactID: AppAssociationTier = sharedByExactIDPeers.isEmpty ? .exclusiveData : .possibleShared

            let exactLibraryDirectories: [(subpath: String, label: String)] = [
                ("Application Support", "Application Support"),
                ("Caches", "Caches"),
                ("Logs", "Logs"),
                ("Containers", "Sandbox Container"),
                ("Saved Application State", "Saved State"),
                ("HTTPStorages", "HTTP Storage"),
                ("WebKit", "WebKit Storage"),
                ("Application Scripts", "Application Scripts")
            ]
            for loc in exactLibraryDirectories {
                let candidate = libraryRoot + "/" + loc.subpath + "/" + bundleID
                registerCandidate(
                    path: candidate,
                    locationKind: loc.label,
                    tier: tierForExactID,
                    confidence: .highBundleID,
                    reasonES: sharedByExactIDPeers.isEmpty
                        ? "Coincidencia exacta por Bundle ID (\(bundleID)) en \(loc.label)."
                        : "Bundle ID (\(bundleID)) compartido también con \(sharedByExactIDPeers.joined(separator: ", ")).",
                    reasonEN: sharedByExactIDPeers.isEmpty
                        ? "Exact Bundle ID match (\(bundleID)) in \(loc.label)."
                        : "Bundle ID (\(bundleID)) is also shared by \(sharedByExactIDPeers.joined(separator: ", ")).",
                    sharedWithApps: sharedByExactIDPeers
                )
            }

            // SavedState has `.savedState` suffix conventionally
            registerCandidate(
                path: libraryRoot + "/Saved Application State/" + bundleID + ".savedState",
                locationKind: "Saved State",
                tier: tierForExactID,
                confidence: .highBundleID,
                reasonES: "Coincidencia exacta por Bundle ID (\(bundleID).savedState).",
                reasonEN: "Exact Bundle ID match (\(bundleID).savedState).",
                sharedWithApps: sharedByExactIDPeers
            )

            // Exact Preferences plist & Cookies & LaunchAgents
            for fileRel in [
                ("Preferences/\(bundleID).plist", "Preferences"),
                ("Cookies/\(bundleID).binarycookies", "Cookies")
            ] {
                registerCandidate(
                    path: libraryRoot + "/" + fileRel.0,
                    locationKind: fileRel.1,
                    tier: tierForExactID,
                    confidence: .highBundleID,
                    reasonES: "Archivo exacto vinculado a Bundle ID (\(bundleID)).",
                    reasonEN: "Exact file linked to Bundle ID (\(bundleID)).",
                    sharedWithApps: sharedByExactIDPeers
                )
            }

            // LaunchAgents in ~/Library/LaunchAgents prefixed by exact bundleID
            let userAgentsDir = libraryRoot + "/LaunchAgents"
            if let agentFiles = try? fm.contentsOfDirectory(atPath: userAgentsDir) {
                for fileName in agentFiles.sorted() {
                    if fileName == "\(bundleID).plist" || fileName.hasPrefix("\(bundleID).") {
                        registerCandidate(
                            path: userAgentsDir + "/" + fileName,
                            locationKind: "User LaunchAgent",
                            tier: tierForExactID,
                            confidence: .highBundleID,
                            reasonES: "LaunchAgent de usuario asociado al Bundle ID (\(bundleID)).",
                            reasonEN: "User LaunchAgent matched by Bundle ID (\(bundleID)).",
                            sharedWithApps: sharedByExactIDPeers
                        )
                    }
                }
            }

            // Privileged global /Library locations matching exact Bundle ID -> never auto-deleted, clearly shown as pending
            for sysRoot in systemRoots {
                for sub in ["Application Support", "LaunchAgents", "LaunchDaemons", "PrivilegedHelperTools", "Preferences"] {
                    let base = sysRoot + "/" + sub
                    if let items = try? fm.contentsOfDirectory(atPath: base) {
                        for name in items.sorted() {
                            if name == bundleID || name == "\(bundleID).plist" || name.hasPrefix("\(bundleID).") {
                                registerCandidate(
                                    path: base + "/" + name,
                                    locationKind: "System /Library/\(sub)",
                                    tier: .exclusiveData,
                                    confidence: .highBundleID,
                                    reasonES: "Elemento global del sistema coincidente por Bundle ID (\(bundleID)); requiere privilegios.",
                                    reasonEN: "System-wide component matching Bundle ID (\(bundleID)); requires privileges.",
                                    sharedWithApps: sharedByExactIDPeers,
                                    forcePrivileged: true
                                )
                            }
                        }
                    }
                }
            }
        }

        // 2. App Groups & Team ID matches -> ALWAYS evaluated against peer installed apps for shared protection!
        let groupContainersDir = libraryRoot + "/Group Containers"
        if let groupEntries = try? fm.contentsOfDirectory(atPath: groupContainersDir) {
            for folderName in groupEntries.sorted() {
                let matchesDeclaredGroup = app.appGroupIDs.contains(folderName)
                let matchesTeamPrefix = app.teamID.map { folderName.hasPrefix($0 + ".") } ?? false
                let matchesBundleHint = app.bundleID.map {
                    folderName.contains($0) || ($0.split(separator: ".").dropFirst().first.map { folderName.contains(String($0)) } ?? false)
                } ?? false

                guard matchesDeclaredGroup || matchesTeamPrefix || (matchesBundleHint && app.teamID != nil) else {
                    continue
                }

                let sharingPeers = peerApps.filter { peer in
                    if peer.appGroupIDs.contains(folderName) { return true }
                    if let peerTeam = peer.teamID, folderName.hasPrefix(peerTeam + ".") { return true }
                    return false
                }.map(\.name)

                let sharedWarningES = sharingPeers.isEmpty
                    ? "Contenedor de grupo (\(folderName)) vinculado por Team/entitlements; puede compartirse entre apps del mismo desarrollador."
                    : "Contenedor compartido con otra(s) app(s) instalada(s): \(sharingPeers.joined(separator: ", "))."
                let sharedWarningEN = sharingPeers.isEmpty
                    ? "App Group container (\(folderName)) linked by Team ID/entitlements; may be shared across suite apps."
                    : "Group container shared with installed app(s): \(sharingPeers.joined(separator: ", "))."

                registerCandidate(
                    path: groupContainersDir + "/" + folderName,
                    locationKind: "Group Container",
                    tier: .possibleShared,
                    confidence: .mediumTeamOrGroup,
                    reasonES: sharedWarningES,
                    reasonEN: sharedWarningEN,
                    sharedWithApps: sharingPeers
                )
            }
        }

        // Check vendor-level Application Support directory shared by same Team ID / reverse-DNS vendor
        if let bundleID = app.bundleID {
            let parts = bundleID.split(separator: ".").map(String.init)
            if parts.count >= 2 {
                let vendorPrefix = parts[0] + "." + parts[1]
                let vendorName = parts[1]
                let teamPeers = peerApps.filter { peer in
                    (app.teamID != nil && peer.teamID == app.teamID) ||
                    (peer.bundleID?.hasPrefix(vendorPrefix + ".") == true)
                }.map(\.name)

                if !teamPeers.isEmpty && vendorName.count >= 3 && !Self.genericNamesForFuzzySkip.contains(vendorName.lowercased()) {
                    let appSupport = libraryRoot + "/Application Support"
                    if let children = try? fm.contentsOfDirectory(atPath: appSupport) {
                        for child in children.sorted() where child.caseInsensitiveCompare(vendorName) == .orderedSame {
                            registerCandidate(
                                path: appSupport + "/" + child,
                                locationKind: "Vendor Application Support",
                                tier: .possibleShared,
                                confidence: .mediumTeamOrGroup,
                                reasonES: "Carpeta de proveedor compartida con \(teamPeers.joined(separator: ", ")).",
                                reasonEN: "Vendor support folder potentially shared with \(teamPeers.joined(separator: ", ")).",
                                sharedWithApps: teamPeers
                            )
                        }
                    }
                }
            }
        }

        // 3. Name-similarity uncertain matches (NEVER auto-selected!)
        let cleanAppName = app.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanAppName.count >= 4,
           !Self.genericNamesForFuzzySkip.contains(cleanAppName.lowercased()) {
            for (subpath, label) in [
                ("Application Support", "Application Support"),
                ("Caches", "Caches"),
                ("Logs", "Logs")
            ] {
                let candidate = libraryRoot + "/" + subpath + "/" + cleanAppName
                registerCandidate(
                    path: candidate,
                    locationKind: label,
                    tier: .uncertainMatch,
                    confidence: .lowNameOnly,
                    reasonES: "Coincidencia solo por nombre (\(cleanAppName)) sin Bundle ID ni firma verificada; revísala manualmente.",
                    reasonEN: "Name-only similarity (\(cleanAppName)) without verified Bundle ID or code signing; review manually."
                )
            }
        }

        return discovered.values.sorted { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier.sortRank < rhs.tier.sortRank }
            return lhs.path < rhs.path
        }
    }

    private func revalidateTargetBeforeTrash(path: String, expectedIdentity: FileIdentity?) -> Bool {
        var st = stat()
        guard lstat(path, &st) == 0 else { return false }
        let mode = st.st_mode & S_IFMT
        guard mode == S_IFREG || mode == S_IFDIR else { return false }
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        guard st.st_uid == getuid(), access(parent, W_OK) == 0 else {
            return false
        }
        if let expectedIdentity {
            let live = SafetyPolicy.identity(st)
            if live.device != expectedIdentity.device || live.inode != expectedIdentity.inode {
                return false
            }
        }
        if mode == S_IFREG, let openPIDs = try? ProcessInspector.openPIDs(path), !openPIDs.isEmpty {
            return false
        }
        return true
    }
}

private extension AppAssociationTier {
    var sortRank: Int {
        switch self {
        case .exclusiveData: return 0
        case .possibleShared: return 1
        case .uncertainMatch: return 2
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
