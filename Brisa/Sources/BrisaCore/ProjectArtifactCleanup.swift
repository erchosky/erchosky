import Foundation
import Darwin

/// Eligibility decision produced by the dedicated Project Artifacts Cleanup policy (separate from `SafetyPolicy`).
public struct ProjectArtifactCleanupDecision: Equatable, Sendable {
    public let artifactPath: String
    public let allowed: Bool
    public let blockReasonES: String?
    public let blockReasonEN: String?

    public init(
        artifactPath: String,
        allowed: Bool,
        blockReasonES: String? = nil,
        blockReasonEN: String? = nil
    ) {
        self.artifactPath = artifactPath
        self.allowed = allowed
        self.blockReasonES = blockReasonES
        self.blockReasonEN = blockReasonEN
    }
}

/// Project-level summary grouping discovered build/dependency artifacts under one project root.
public struct ProjectArtifactGroup: Equatable, Sendable, Identifiable {
    public var id: String { projectRoot }
    public let projectName: String
    public let projectRoot: String
    public let primaryEcosystem: String
    public let anchorFiles: [String]
    public let preservedProjectFiles: [String]
    public let artifacts: [ProjectArtifactAuditEntry]
    public let totalAllocatedBytes: Int64
    public let totalLogicalBytes: Int64
    public let cleanableAllocatedBytes: Int64
    public let cleanableLogicalBytes: Int64
    public let cleanableCount: Int
    public let blockedCount: Int
}

/// Feature-specific safety policy for moving verified project build/dependency artifacts to Trash.
/// Preserves repositories, worktrees, source files, manifests, lockfiles, tracked files, subrepos, and symlinks.
public struct ProjectArtifactCleanupPolicy: Sendable {
    public static let protectedManifestAndSourceNames: Set<String> = [
        ".git", ".gitignore", ".gitmodules", ".gitattributes",
        "Package.swift", "Package.resolved",
        "Cargo.toml", "Cargo.lock",
        "package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lock", "bun.lockb",
        "Podfile", "Podfile.lock",
        "pyproject.toml", "requirements.txt", "setup.py", "poetry.lock", "uv.lock",
        "pom.xml", "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts", "gradle.lockfile",
        "mix.exs", "mix.lock", "pubspec.yaml", "pubspec.lock", "CMakeLists.txt",
        "go.mod", "go.sum", "Makefile", "src", "Sources", "Tests", "lib", "app"
    ]

    public let home: String
    public let readPolicy: ReadAuthorizationPolicy
    public let protectedPaths: [String]
    public let checkActiveProcesses: Bool
    public let recentChildGraceSeconds: TimeInterval

    public init(
        home: String = NSHomeDirectory(),
        readPolicy: ReadAuthorizationPolicy,
        protectedPaths: [String] = [],
        checkActiveProcesses: Bool = true,
        recentChildGraceSeconds: TimeInterval = 300
    ) {
        self.home = Paths.normalized(home)
        self.readPolicy = readPolicy
        self.protectedPaths = protectedPaths.map(Paths.normalized)
        self.checkActiveProcesses = checkActiveProcesses
        self.recentChildGraceSeconds = recentChildGraceSeconds
    }

    public static func groupByProject(
        _ artifacts: [ProjectArtifactAuditEntry]
    ) -> [ProjectArtifactGroup] {
        let grouped = Dictionary(grouping: artifacts) { Paths.normalized($0.projectRoot) }
        return grouped.keys.sorted().compactMap { root in
            guard let items = grouped[root]?.sorted(by: { $0.artifactName < $1.artifactName }),
                  let first = items.first else {
                return nil
            }
            let anchors = Array(Set(items.map(\.anchorFile))).sorted()
            let preserved = discoverPreservedProjectFiles(in: root, anchors: anchors)
            let ecosystems = Array(Set(items.map(\.ecosystem))).sorted()
            let primaryEco = ecosystems.joined(separator: " / ")
            var totalAlloc: Int64 = 0
            var totalLog: Int64 = 0
            var cleanAlloc: Int64 = 0
            var cleanLog: Int64 = 0
            var cleanCount = 0
            var blockedCount = 0
            for item in items {
                totalAlloc = ByteTotals.adding(totalAlloc, item.allocatedBytes)
                totalLog = ByteTotals.adding(totalLog, item.logicalBytes)
                if item.state == .anchoredIdleCandidate {
                    cleanCount += 1
                    cleanAlloc = ByteTotals.adding(cleanAlloc, item.allocatedBytes)
                    cleanLog = ByteTotals.adding(cleanLog, item.logicalBytes)
                } else {
                    blockedCount += 1
                }
            }
            return ProjectArtifactGroup(
                projectName: first.projectName,
                projectRoot: root,
                primaryEcosystem: primaryEco,
                anchorFiles: anchors,
                preservedProjectFiles: preserved,
                artifacts: items,
                totalAllocatedBytes: totalAlloc,
                totalLogicalBytes: totalLog,
                cleanableAllocatedBytes: cleanAlloc,
                cleanableLogicalBytes: cleanLog,
                cleanableCount: cleanCount,
                blockedCount: blockedCount
            )
        }
    }

    public static func discoverPreservedProjectFiles(in projectRoot: String, anchors: [String]) -> [String] {
        var found: [String] = []
        let candidates = Array(Set(protectedManifestAndSourceNames.union(anchors))).sorted()
        for name in candidates {
            let full = URL(fileURLWithPath: projectRoot, isDirectory: true).appendingPathComponent(name).path
            var st = stat()
            if lstat(full, &st) == 0 {
                found.append(name)
            }
        }
        return found
    }

    public func evaluate(_ entry: ProjectArtifactAuditEntry, now: Date = Date()) -> ProjectArtifactCleanupDecision {
        let artifactPath = Paths.normalized(entry.artifactPath)
        let projectRoot = Paths.normalized(entry.projectRoot)

        guard readPolicy.projectRoots.contains(where: { SafetyPolicy.within(artifactPath, Paths.normalized($0)) }) else {
            return ProjectArtifactCleanupDecision(
                artifactPath: artifactPath,
                allowed: false,
                blockReasonES: "La ruta está fuera de las carpetas de proyectos autorizadas.",
                blockReasonEN: "Artifact path is outside authorized project roots."
            )
        }

        if readPolicy.evaluate(artifactPath, checkSymlinks: true) != .allowed {
            return ProjectArtifactCleanupDecision(
                artifactPath: artifactPath,
                allowed: false,
                blockReasonES: "Bloqueado por la política de lectura o rutas protegidas.",
                blockReasonEN: "Blocked by read authorization or protected path rules."
            )
        }

        if Paths.containsAncestor(of: artifactPath, in: Set(protectedPaths)) {
            return ProjectArtifactCleanupDecision(
                artifactPath: artifactPath,
                allowed: false,
                blockReasonES: "La ruta o una carpeta superior está marcada como protegida.",
                blockReasonEN: "This path or an ancestor folder is protected by the user."
            )
        }

        guard artifactPath != projectRoot, SafetyPolicy.within(artifactPath, projectRoot) else {
            return ProjectArtifactCleanupDecision(
                artifactPath: artifactPath,
                allowed: false,
                blockReasonES: "El artefacto debe estar contenido estrictamente dentro de la carpeta del proyecto.",
                blockReasonEN: "Artifact must be strictly contained inside its project folder."
            )
        }

        let dirName = URL(fileURLWithPath: artifactPath).lastPathComponent
        guard !Self.protectedManifestAndSourceNames.contains(dirName) else {
            return ProjectArtifactCleanupDecision(
                artifactPath: artifactPath,
                allowed: false,
                blockReasonES: "Protegido: nunca se eliminan manifiestos, lockfiles, repositorios ni carpetas fuente.",
                blockReasonEN: "Protected: repositories, manifests, lockfiles, and source folders are never deleted."
            )
        }

        let anchorPath = URL(fileURLWithPath: projectRoot, isDirectory: true)
            .appendingPathComponent(entry.anchorFile)
            .path
        var anchorStat = stat()
        guard lstat(anchorPath, &anchorStat) == 0 else {
            return ProjectArtifactCleanupDecision(
                artifactPath: artifactPath,
                allowed: false,
                blockReasonES: "No se encontró el archivo ancla (\(entry.anchorFile)); origen no verificable.",
                blockReasonEN: "Anchor file (\(entry.anchorFile)) missing; artifact origin cannot be verified."
            )
        }

        switch entry.state {
        case .anchoredIdleCandidate:
            break
        case .blockedTrackedByGit:
            return ProjectArtifactCleanupDecision(
                artifactPath: artifactPath,
                allowed: false,
                blockReasonES: "Bloqueado: contiene archivos rastreados por Git.",
                blockReasonEN: "Blocked: contains files tracked by Git."
            )
        case .blockedContainsSymlink:
            return ProjectArtifactCleanupDecision(
                artifactPath: artifactPath,
                allowed: false,
                blockReasonES: "Bloqueado: el artefacto o su árbol contiene enlaces simbólicos.",
                blockReasonEN: "Blocked: artifact or its subtree contains symbolic links."
            )
        case .blockedNestedSubrepository:
            return ProjectArtifactCleanupDecision(
                artifactPath: artifactPath,
                allowed: false,
                blockReasonES: "Bloqueado: contiene un subrepositorio Git independiente.",
                blockReasonEN: "Blocked: contains its own nested Git subrepository."
            )
        case .blockedActiveOrRecent:
            return ProjectArtifactCleanupDecision(
                artifactPath: artifactPath,
                allowed: false,
                blockReasonES: "Bloqueado: proyecto activo o modificado recientemente.",
                blockReasonEN: "Blocked: active process detected or recently modified."
            )
        case .blockedUnverifiedGitOrUsage:
            return ProjectArtifactCleanupDecision(
                artifactPath: artifactPath,
                allowed: false,
                blockReasonES: "Bloqueado: no pudo verificarse por completo su origen en Git o estado de uso.",
                blockReasonEN: "Blocked: Git tracking or active usage could not be fully verified."
            )
        }

        if entry.containsSymlink || entry.isNestedSubrepository || (entry.trackedFileCount ?? 1) > 0 || !entry.activeProcessPIDs.isEmpty {
            return ProjectArtifactCleanupDecision(
                artifactPath: artifactPath,
                allowed: false,
                blockReasonES: "Bloqueado por comprobación estricta de seguridad (Git/symlinks/uso).",
                blockReasonEN: "Blocked by strict safety check (Git/symlinks/active handles)."
            )
        }

        if checkActiveProcesses && !entry.usageVerified {
            return ProjectArtifactCleanupDecision(
                artifactPath: artifactPath,
                allowed: false,
                blockReasonES: "No se pudo verificar si hay procesos usando esta carpeta.",
                blockReasonEN: "Could not verify whether processes are currently using this folder."
            )
        }

        if let childMod = entry.latestChildModifiedAt,
           recentChildGraceSeconds > 0,
           now.timeIntervalSince(childMod) < recentChildGraceSeconds {
            return ProjectArtifactCleanupDecision(
                artifactPath: artifactPath,
                allowed: false,
                blockReasonES: "Bloqueado: archivos internos modificados hace menos de \(Int(recentChildGraceSeconds / 60)) minutos.",
                blockReasonEN: "Blocked: files inside were written less than \(Int(recentChildGraceSeconds / 60)) minutes ago."
            )
        }

        return ProjectArtifactCleanupDecision(artifactPath: artifactPath, allowed: true)
    }

    public func buildPlan(
        selectedArtifacts: [ProjectArtifactAuditEntry],
        now: Date = Date()
    ) -> OperationPlan {
        var resources: [OperationAffectedResource] = []
        var blockers: [OperationBlocker] = []
        var seenPaths = Set<String>()
        var totalAlloc: Int64 = 0
        var totalLog: Int64 = 0
        var preservedSet = Set<String>()
        var rebuildLinesES: [String] = []
        var rebuildLinesEN: [String] = []

        for item in selectedArtifacts.sorted(by: { $0.artifactPath < $1.artifactPath }) {
            let norm = Paths.normalized(item.artifactPath)
            guard seenPaths.insert(norm).inserted else { continue }
            let decision = evaluate(item, now: now)
            let preserved = Self.discoverPreservedProjectFiles(in: item.projectRoot, anchors: [item.anchorFile])
            preservedSet.formUnion(preserved.map { "\(item.projectName): \($0)" })

            resources.append(OperationAffectedResource(
                id: item.id,
                labelES: "\(item.projectName) · \(item.artifactName) (\(item.ecosystem))",
                labelEN: "\(item.projectName) · \(item.artifactName) (\(item.ecosystem))",
                pathOrIdentifier: norm,
                sizeBytes: item.allocatedBytes,
                logicalBytes: item.logicalBytes,
                sizeBasis: .measured,
                mechanism: .trash,
                blockedReasonES: decision.blockReasonES,
                blockedReasonEN: decision.blockReasonEN
            ))

            if decision.allowed {
                totalAlloc = ByteTotals.adding(totalAlloc, item.allocatedBytes)
                totalLog = ByteTotals.adding(totalLog, item.logicalBytes)
                if !item.rebuildCommand.isEmpty {
                    rebuildLinesES.append("\(item.projectName) (\(item.artifactName)): \(item.rebuildCommand) — \(item.rebuildRequirementsES)")
                    rebuildLinesEN.append("\(item.projectName) (\(item.artifactName)): \(item.rebuildCommand) — \(item.rebuildRequirementsEN)")
                }
            } else {
                blockers.append(OperationBlocker(
                    resourceID: item.id,
                    reasonES: decision.blockReasonES ?? "Bloqueado por seguridad.",
                    reasonEN: decision.blockReasonEN ?? "Blocked by safety policy.",
                    canRecheck: true
                ))
            }
        }

        let actionableCount = resources.filter { !$0.isBlocked }.count
        if selectedArtifacts.isEmpty {
            blockers.append(OperationBlocker(
                reasonES: "Selecciona al menos un artefacto elegible para revisar el plan.",
                reasonEN: "Select at least one eligible artifact to review the plan."
            ))
        } else if actionableCount == 0 {
            blockers.append(OperationBlocker(
                reasonES: "Ninguno de los artefactos seleccionados supera todas las comprobaciones de seguridad.",
                reasonEN: "None of the selected artifacts pass all safety checks.",
                canRecheck: true
            ))
        }

        let preservedList = preservedSet.sorted().prefix(12).joined(separator: ", ")
        let preservedES = preservedList.isEmpty
            ? "Se conservan íntegramente el código fuente, repositorios Git, worktrees, manifiestos y lockfiles."
            : "Se conservan el repositorio Git, worktrees, archivos fuente y manifiestos/lockfiles (\(preservedList))."
        let preservedEN = preservedList.isEmpty
            ? "Source files, Git repositories, worktrees, manifests, and lockfiles remain completely untouched."
            : "Git repository, worktrees, source files, and manifests/lockfiles remain untouched (\(preservedList))."

        let regenES = rebuildLinesES.isEmpty
            ? "Brisa nunca ejecuta scripts del proyecto. Reconstruye manualmente según el ecosistema desde la carpeta del proyecto."
            : rebuildLinesES.joined(separator: "\n") + "\nNota: Brisa no ejecutará estos comandos automáticamente."
        let regenEN = rebuildLinesEN.isEmpty
            ? "Brisa never runs project scripts automatically. Rebuild manually from each project folder when needed."
            : rebuildLinesEN.joined(separator: "\n") + "\nNote: Brisa will never run these commands automatically."

        return OperationPlan(
            domain: .projectArtifacts,
            titleES: "Mover \(actionableCount) artefacto(s) de proyecto a la Papelera",
            titleEN: "Move \(actionableCount) project artifact(s) to Trash",
            scopeDescriptionES: "Solo se moverán a la Papelera los directorios de artefactos concretos seleccionados que cumplan todas las verificaciones de Git, enlaces simbólicos, subrepositorios y uso activo.",
            scopeDescriptionEN: "Only the specifically selected artifact directories passing Git tracking, symlink, nested subrepository, and active-usage checks will move to Trash.",
            affectedResources: resources,
            preservedSummaryES: preservedES,
            preservedSummaryEN: preservedEN,
            totalBytes: totalAlloc,
            logicalBytes: totalLog,
            sizeBasis: .measured,
            sizeNoteES: "Tamaño medido en disco (asignado en bloque y lógico antes de mover a la Papelera). La fecha de modificación no garantiza ausencia de uso futuro.",
            sizeNoteEN: "Measured on-disk size (allocated and logical bytes prior to Trash). Modification timestamps do not prove last human use.",
            regenerationES: regenES,
            regenerationEN: regenEN,
            mechanism: .trash,
            restorability: .trashRestore,
            restorabilityNoteES: "Cada carpeta de artefacto se mueve de forma atómica a la Papelera de macOS para que puedas devolverla si la necesitas.",
            restorabilityNoteEN: "Each artifact folder moves atomically to macOS Trash so you can put it back if needed.",
            blockers: blockers,
            canExecute: actionableCount > 0
        )
    }
}

/// Scans and executes Trash cleanup for selected project artifacts with pre-action revalidation and journal logging.
public final class ProjectArtifactCleaner: @unchecked Sendable {
    private let journal: Journal
    private let mover: TrashMoving
    private let policy: ProjectArtifactCleanupPolicy
    private let gitExecutable: String
    private let maxEntriesPerArtifact: Int
    private let lock = NSLock()

    public init(
        journal: Journal,
        policy: ProjectArtifactCleanupPolicy,
        gitExecutable: String = ExecutableLocator.resolve(name: "git") ?? "/usr/bin/git",
        maxEntriesPerArtifact: Int = 100_000,
        mover: TrashMoving = SystemTrashMover()
    ) {
        self.journal = journal
        self.policy = policy
        self.gitExecutable = gitExecutable
        self.maxEntriesPerArtifact = maxEntriesPerArtifact
        self.mover = mover
    }

    public func scanGroups(
        authorizedRoots: [String],
        maxDepth: Int = 5,
        now: Date = Date(),
        control: ScanControl = ScanControl()
    ) -> [ProjectArtifactGroup] {
        let artifacts = WorktreeAndProjectDetector.scanProjectArtifacts(
            authorizedRoots: authorizedRoots,
            readPolicy: policy.readPolicy,
            maxDepth: maxDepth,
            gitExecutable: gitExecutable,
            checkActiveProcesses: policy.checkActiveProcesses,
            now: now,
            control: control,
            maxEntriesPerArtifact: maxEntriesPerArtifact
        )
        return ProjectArtifactCleanupPolicy.groupByProject(artifacts)
    }

    public func execute(
        plan: OperationPlan,
        targets: [ProjectArtifactAuditEntry],
        cancellation: CancellationFlag = CancellationFlag(),
        now: Date = Date(),
        onProgress: (@Sendable (Int, Int, String) -> Void)? = nil
    ) throws -> OperationExecutionReport {
        guard lock.try() else {
            throw BrisaError.rejected("Another project artifact cleanup is already running")
        }
        defer { lock.unlock() }
        guard plan.domain == .projectArtifacts, plan.canExecute else {
            throw BrisaError.rejected("Project artifact cleanup plan cannot execute")
        }

        _ = try journal.entries()
        let allowedIDs = Set(plan.actionableResources.map(\.id))
        let chosenTargets = targets.filter { allowedIDs.contains($0.id) }
        guard !chosenTargets.isEmpty else {
            throw BrisaError.invalid("No eligible project artifacts selected")
        }

        let planEntry = try OperationJournalRecorder.recordPlan(plan, journal: journal, home: policy.home)
        var completed: [String] = []
        var rejected: [String] = []
        var failed: [String] = []
        var skipped: [String] = []
        var entries: [JournalEntry] = [planEntry]
        var reclaimedBytes: Int64 = 0
        var cancelledDuringRun = false

        for (index, item) in chosenTargets.enumerated() {
            if cancellation.isCancelled {
                cancelledDuringRun = true
                skipped.append(contentsOf: chosenTargets[index...].map(\.artifactPath))
                break
            }
            onProgress?(index, chosenTargets.count, item.artifactPath)

            let freeBefore = OperationJournalRecorder.currentAvailableCapacity(for: policy.home)
            var itemEntry = JournalEntry(
                operation: "project_artifact.trash",
                originalPath: item.artifactPath,
                size: item.logicalBytes,
                allocatedBytes: item.allocatedBytes,
                identity: item.identity ?? FileIdentity(device: 0, inode: 0, size: item.logicalBytes, modified: 0, changed: 0),
                status: "intent",
                freeSpaceBefore: freeBefore,
                domain: OperationDomain.projectArtifacts.rawValue,
                mechanism: OperationMechanism.trash.rawValue,
                restorable: false,
                planID: plan.id,
                summaryTitle: "\(item.projectName) · \(item.artifactName)"
            )

            // Revalidate live state right before moving to Trash.
            let initialDecision = policy.evaluate(item, now: now)
            guard initialDecision.allowed else {
                itemEntry.status = OperationOutcomeStatus.rejected.rawValue
                itemEntry.outcomeKind = OperationOutcomeStatus.rejected.rawValue
                itemEntry.error = initialDecision.blockReasonEN
                itemEntry.freeSpaceAfter = OperationJournalRecorder.currentAvailableCapacity(for: policy.home)
                try journal.append(itemEntry)
                entries.append(itemEntry)
                rejected.append(item.artifactPath)
                continue
            }

            let fresh = WorktreeAndProjectDetector.inspectSingleProjectArtifact(
                artifactPath: item.artifactPath,
                artifactName: item.artifactName,
                projectRoot: item.projectRoot,
                anchorFile: item.anchorFile,
                ecosystem: item.ecosystem,
                readPolicy: policy.readPolicy,
                gitExecutable: gitExecutable,
                checkActiveProcesses: policy.checkActiveProcesses,
                now: now,
                control: ScanControl(cancellation: cancellation),
                maxEntriesPerArtifact: maxEntriesPerArtifact
            )

            let liveDecision = policy.evaluate(fresh, now: now)
            guard liveDecision.allowed else {
                let reason = liveDecision.blockReasonEN ?? "Blocked upon live revalidation"
                itemEntry.status = OperationOutcomeStatus.rejected.rawValue
                itemEntry.outcomeKind = OperationOutcomeStatus.rejected.rawValue
                itemEntry.error = reason
                itemEntry.freeSpaceAfter = OperationJournalRecorder.currentAvailableCapacity(for: policy.home)
                try journal.append(itemEntry)
                entries.append(itemEntry)
                rejected.append(item.artifactPath)
                continue
            }

            if let expectedID = item.identity, let liveID = fresh.identity,
               (expectedID.device != liveID.device || expectedID.inode != liveID.inode) {
                itemEntry.status = OperationOutcomeStatus.rejected.rawValue
                itemEntry.outcomeKind = OperationOutcomeStatus.rejected.rawValue
                itemEntry.error = "Artifact directory inode changed after analysis"
                itemEntry.freeSpaceAfter = OperationJournalRecorder.currentAvailableCapacity(for: policy.home)
                try journal.append(itemEntry)
                entries.append(itemEntry)
                rejected.append(item.artifactPath)
                continue
            }

            do {
                try journal.append(itemEntry)
                let trashURL = try mover.move(URL(fileURLWithPath: fresh.artifactPath))
                itemEntry.trashPath = trashURL?.path
                itemEntry.status = "trashed"
                itemEntry.outcomeKind = OperationOutcomeStatus.completed.rawValue
                itemEntry.restorable = true
                itemEntry.freeSpaceAfter = OperationJournalRecorder.currentAvailableCapacity(for: policy.home)
                try journal.append(itemEntry)
                entries.append(itemEntry)
                completed.append(item.artifactPath)
                reclaimedBytes = ByteTotals.adding(reclaimedBytes, fresh.allocatedBytes)
            } catch {
                itemEntry.status = OperationOutcomeStatus.failed.rawValue
                itemEntry.outcomeKind = OperationOutcomeStatus.failed.rawValue
                itemEntry.restorable = false
                itemEntry.error = error.localizedDescription
                itemEntry.freeSpaceAfter = OperationJournalRecorder.currentAvailableCapacity(for: policy.home)
                try journal.append(itemEntry)
                entries.append(itemEntry)
                failed.append(item.artifactPath)
            }
        }

        let outcome = OperationJournalRecorder.resolveBatchOutcome(
            completed: completed.count,
            rejected: rejected.count,
            failed: failed.count,
            cancelled: cancelledDuringRun
        )
        let detailNote = cancelledDuringRun && !completed.isEmpty
            ? "\(completed.count) moved to Trash; cancelled before \(skipped.count) remaining item(s). Completed Trash moves were not rolled back."
            : "\(completed.count) completed, \(rejected.count) rejected, \(failed.count) failed, \(skipped.count) cancelled."
        let detailNoteES = cancelledDuringRun && !completed.isEmpty
            ? "\(completed.count) enviado(s) a Papelera; cancelado antes de \(skipped.count) elemento(s) restante(s). Los traslados completados no se revirtieron."
            : "\(completed.count) completado(s), \(rejected.count) rechazado(s), \(failed.count) fallido(s), \(skipped.count) cancelado(s)."
        let finalEntry = try OperationJournalRecorder.finalizePlan(
            plan,
            planEntry: planEntry,
            outcome: outcome,
            completedCount: completed.count,
            skippedOrFailedCount: rejected.count + failed.count + skipped.count,
            detailNote: detailNote,
            detailNoteES: detailNoteES,
            restorable: !completed.isEmpty,
            journal: journal,
            home: policy.home
        )
        entries[0] = finalEntry

        let summaryES: String
        let summaryEN: String
        switch outcome {
        case .completed:
            summaryES = "Se movieron \(completed.count) artefacto(s) a la Papelera (\(Formatting.bytes(reclaimedBytes)))."
            summaryEN = "Moved \(completed.count) project artifact(s) to Trash (\(Formatting.bytes(reclaimedBytes)))."
        case .partial:
            summaryES = "Resultado parcial: \(completed.count) a la Papelera, \(rejected.count + failed.count + skipped.count) omitido(s)/fallido(s). Lo ya enviado a Papelera no se revirtió automáticamente."
            summaryEN = "Partial outcome: \(completed.count) moved to Trash, \(rejected.count + failed.count + skipped.count) skipped/failed. Items already in Trash were not rolled back."
        case .cancelled:
            summaryES = "Operación cancelada antes de mover artefactos."
            summaryEN = "Operation cancelled before moving any artifacts."
        case .rejected:
            summaryES = "Todos los artefactos seleccionados fueron rechazados al revalidar sus protecciones."
            summaryEN = "All selected artifacts were rejected upon safety revalidation."
        case .failed, .planned:
            summaryES = "La limpieza falló al mover los artefactos seleccionados."
            summaryEN = "Cleanup failed while moving selected artifacts."
        }

        return OperationExecutionReport(
            planID: plan.id,
            domain: .projectArtifacts,
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
}
