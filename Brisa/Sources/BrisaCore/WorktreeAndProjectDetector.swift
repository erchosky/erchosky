import Foundation
import Darwin

public enum WorktreeAuditStatus: String, Codable, CaseIterable, Sendable {
    case cleanIdle = "clean_idle"
    case dirtyUncommitted = "dirty_uncommitted"
    case unpushedCommits = "unpushed_commits"
    case locked = "locked"
    case inUseProcess = "in_use_process"
    case recentlyModified = "recently_modified"
    case staleMissingDirectory = "stale_missing_directory"
    case inspectionFailedUnknown = "inspection_failed_unknown"
}

public enum WorktreeIntegrationEvidence: String, Codable, CaseIterable, Sendable {
    case isDefaultBranch = "is_default_branch"
    case mergedIntoDefaultBranch = "merged_into_default_branch"
    case notMergedIntoDefaultBranch = "not_merged_into_default_branch"
    case unknown = "unknown"
}

public struct WorktreeAuditEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(repositoryRoot)::\(worktreePath)" }
    public let worktreePath: String
    public let repositoryRoot: String
    public let branchOrHead: String
    public let headSHA: String?
    public let isMainWorktree: Bool
    public let isLinkedWorktree: Bool
    public let status: WorktreeAuditStatus
    public let dirtyCount: Int?
    public let unpushedCommitCount: Int?
    public let isLocked: Bool
    public let lockReason: String?
    public let activeProcessPIDs: [Int32]
    public let usageVerified: Bool
    public let integrationEvidence: WorktreeIntegrationEvidence
    public let allocatedBytes: Int64
    public let logicalBytes: Int64
    public let inventoryOnly: Bool
    public let selectionAllowed: Bool
    public let explanationES: String
    public let explanationEN: String

    public init(
        worktreePath: String,
        repositoryRoot: String,
        branchOrHead: String,
        headSHA: String? = nil,
        isMainWorktree: Bool,
        isLinkedWorktree: Bool,
        status: WorktreeAuditStatus,
        dirtyCount: Int? = nil,
        unpushedCommitCount: Int? = nil,
        isLocked: Bool = false,
        lockReason: String? = nil,
        activeProcessPIDs: [Int32] = [],
        usageVerified: Bool = false,
        integrationEvidence: WorktreeIntegrationEvidence = .unknown,
        allocatedBytes: Int64 = 0,
        logicalBytes: Int64 = 0,
        explanationES: String,
        explanationEN: String
    ) {
        self.worktreePath = worktreePath
        self.repositoryRoot = repositoryRoot
        self.branchOrHead = branchOrHead
        self.headSHA = headSHA
        self.isMainWorktree = isMainWorktree
        self.isLinkedWorktree = isLinkedWorktree
        self.status = status
        self.dirtyCount = dirtyCount
        self.unpushedCommitCount = unpushedCommitCount
        self.isLocked = isLocked
        self.lockReason = lockReason
        self.activeProcessPIDs = activeProcessPIDs
        self.usageVerified = usageVerified
        self.integrationEvidence = integrationEvidence
        self.allocatedBytes = allocatedBytes
        self.logicalBytes = logicalBytes
        self.inventoryOnly = true
        self.selectionAllowed = false
        self.explanationES = explanationES
        self.explanationEN = explanationEN
    }
}

public enum ProjectArtifactSafetyState: String, Codable, CaseIterable, Sendable {
    case anchoredIdleCandidate = "anchored_idle_candidate"
    case blockedTrackedByGit = "blocked_tracked_by_git"
    case blockedContainsSymlink = "blocked_contains_symlink"
    case blockedNestedSubrepository = "blocked_nested_subrepository"
    case blockedActiveOrRecent = "blocked_active_or_recent"
    case blockedUnverifiedGitOrUsage = "blocked_unverified_git_or_usage"
}

public struct ProjectArtifactAuditEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String { artifactPath }
    public let artifactPath: String
    public let artifactName: String
    public let projectRoot: String
    public let projectName: String
    public let anchorFile: String
    public let ecosystem: String
    public let state: ProjectArtifactSafetyState
    public let trackedFileCount: Int?
    public let containsSymlink: Bool
    public let isNestedSubrepository: Bool
    public let activeProcessPIDs: [Int32]
    public let usageVerified: Bool
    public let allocatedBytes: Int64
    public let logicalBytes: Int64
    public let modifiedAt: Date?
    public let latestChildModifiedAt: Date?
    public let identity: FileIdentity?
    public let regenerableReasonES: String
    public let regenerableReasonEN: String
    public let rebuildRequirementsES: String
    public let rebuildRequirementsEN: String
    public let rebuildCommand: String
    public let activeBuildWarnings: [String]
    public let usageUncertaintyES: String
    public let usageUncertaintyEN: String
    public let inventoryOnly: Bool
    public let selectionAllowed: Bool
    public let explanationES: String
    public let explanationEN: String

    public init(
        artifactPath: String,
        artifactName: String,
        projectRoot: String,
        projectName: String? = nil,
        anchorFile: String,
        ecosystem: String,
        state: ProjectArtifactSafetyState,
        trackedFileCount: Int? = nil,
        containsSymlink: Bool = false,
        isNestedSubrepository: Bool = false,
        activeProcessPIDs: [Int32] = [],
        usageVerified: Bool = false,
        allocatedBytes: Int64 = 0,
        logicalBytes: Int64 = 0,
        modifiedAt: Date? = nil,
        latestChildModifiedAt: Date? = nil,
        identity: FileIdentity? = nil,
        regenerableReasonES: String = "",
        regenerableReasonEN: String = "",
        rebuildRequirementsES: String = "",
        rebuildRequirementsEN: String = "",
        rebuildCommand: String = "",
        activeBuildWarnings: [String] = [],
        usageUncertaintyES: String = "",
        usageUncertaintyEN: String = "",
        explanationES: String,
        explanationEN: String
    ) {
        self.artifactPath = artifactPath
        self.artifactName = artifactName
        self.projectRoot = projectRoot
        self.projectName = projectName ?? URL(fileURLWithPath: projectRoot).lastPathComponent
        self.anchorFile = anchorFile
        self.ecosystem = ecosystem
        self.state = state
        self.trackedFileCount = trackedFileCount
        self.containsSymlink = containsSymlink
        self.isNestedSubrepository = isNestedSubrepository
        self.activeProcessPIDs = activeProcessPIDs
        self.usageVerified = usageVerified
        self.allocatedBytes = allocatedBytes
        self.logicalBytes = logicalBytes
        self.modifiedAt = modifiedAt
        self.latestChildModifiedAt = latestChildModifiedAt
        self.identity = identity
        self.regenerableReasonES = regenerableReasonES
        self.regenerableReasonEN = regenerableReasonEN
        self.rebuildRequirementsES = rebuildRequirementsES
        self.rebuildRequirementsEN = rebuildRequirementsEN
        self.rebuildCommand = rebuildCommand
        self.activeBuildWarnings = activeBuildWarnings
        self.usageUncertaintyES = usageUncertaintyES
        self.usageUncertaintyEN = usageUncertaintyEN
        self.inventoryOnly = true
        self.selectionAllowed = false
        self.explanationES = explanationES
        self.explanationEN = explanationEN
    }
}

/// Combined result of scanning authorized roots once for both Git worktrees and contextual project build artifacts.
public struct WorktreeAndProjectScanResult: Sendable {
    public let worktrees: [WorktreeAuditEntry]
    public let projectArtifacts: [ProjectArtifactAuditEntry]

    public init(worktrees: [WorktreeAuditEntry], projectArtifacts: [ProjectArtifactAuditEntry]) {
        self.worktrees = worktrees
        self.projectArtifacts = projectArtifacts
    }
}

public enum WorktreeAndProjectDetector {
    private static let prunedDirectoryNames: Set<String> = [
        "node_modules", ".build", "build", "target", "DerivedData", "Pods",
        ".gradle", ".cxx", ".kotlin", ".next", ".nuxt", ".svelte-kit", ".turbo",
        ".parcel-cache", ".angular", "dist", ".venv", "venv", ".tox",
        ".mypy_cache", ".pytest_cache", ".ruff_cache", "_build", ".dart_tool"
    ]

    /// Discovers Git repositories and project-anchored build artifacts in a single directory traversal across authorized roots.
    public static func scanAll(
        authorizedRoots: [String],
        readPolicy: ReadAuthorizationPolicy,
        maxDepth: Int = 5,
        maxVisitedDirectories: Int = 2_500,
        maxVisitedEntries: Int = 50_000,
        gitExecutable: String = "/usr/bin/git",
        checkActiveProcesses: Bool = true,
        now: Date = Date(),
        control: ScanControl = ScanControl()
    ) -> WorktreeAndProjectScanResult {
        let walked = walkAuthorizedDirectories(
            authorizedRoots: authorizedRoots,
            readPolicy: readPolicy,
            maxDepth: maxDepth,
            maxVisitedDirectories: maxVisitedDirectories,
            maxVisitedEntries: maxVisitedEntries,
            collectGitRoots: true,
            collectArtifacts: true,
            gitExecutable: gitExecutable,
            checkActiveProcesses: checkActiveProcesses,
            now: now,
            control: control
        )
        let worktrees = auditRepositoryWorktrees(
            repoRoots: walked.repoRoots,
            readPolicy: readPolicy,
            gitExecutable: gitExecutable,
            checkActiveProcesses: checkActiveProcesses,
            now: now,
            control: control
        )
        return WorktreeAndProjectScanResult(
            worktrees: worktrees,
            projectArtifacts: walked.artifacts.sorted { $0.artifactPath < $1.artifactPath }
        )
    }

    /// Discovers Git repositories and linked worktrees within authorized roots and audits each one in read-only mode.
    public static func scanWorktrees(
        authorizedRoots: [String],
        readPolicy: ReadAuthorizationPolicy,
        maxDepth: Int = 5,
        maxVisitedDirectories: Int = 2_500,
        maxVisitedEntries: Int = 50_000,
        gitExecutable: String = "/usr/bin/git",
        checkActiveProcesses: Bool = true,
        now: Date = Date(),
        control: ScanControl = ScanControl()
    ) -> [WorktreeAuditEntry] {
        let walked = walkAuthorizedDirectories(
            authorizedRoots: authorizedRoots,
            readPolicy: readPolicy,
            maxDepth: maxDepth,
            maxVisitedDirectories: maxVisitedDirectories,
            maxVisitedEntries: maxVisitedEntries,
            collectGitRoots: true,
            collectArtifacts: false,
            gitExecutable: gitExecutable,
            checkActiveProcesses: checkActiveProcesses,
            now: now,
            control: control
        )
        return auditRepositoryWorktrees(
            repoRoots: walked.repoRoots,
            readPolicy: readPolicy,
            gitExecutable: gitExecutable,
            checkActiveProcesses: checkActiveProcesses,
            now: now,
            control: control
        )
    }

    private static func auditRepositoryWorktrees(
        repoRoots: [String],
        readPolicy: ReadAuthorizationPolicy,
        gitExecutable: String,
        checkActiveProcesses: Bool,
        now: Date,
        control: ScanControl
    ) -> [WorktreeAuditEntry] {
        var entries: [WorktreeAuditEntry] = []
        var seenPairs = Set<String>()

        for repoRoot in repoRoots {
            if control.shouldStop { break }
            let discovered = inspectRepositoryWorktrees(
                repositoryPath: repoRoot,
                readPolicy: readPolicy,
                gitExecutable: gitExecutable,
                checkActiveProcesses: checkActiveProcesses,
                now: now,
                control: control
            )
            for item in discovered {
                let key = "\(item.repositoryRoot)::\(item.worktreePath)"
                if seenPairs.insert(key).inserted {
                    entries.append(item)
                }
            }
        }
        return entries.sorted { ($0.repositoryRoot, $0.worktreePath) < ($1.repositoryRoot, $1.worktreePath) }
    }

    /// Inspects a single Git repository and all of its worktrees reported by `git worktree list --porcelain -z`.
    public static func inspectRepositoryWorktrees(
        repositoryPath rawPath: String,
        readPolicy: ReadAuthorizationPolicy,
        gitExecutable: String = "/usr/bin/git",
        checkActiveProcesses: Bool = true,
        now: Date = Date(),
        control: ScanControl = ScanControl()
    ) -> [WorktreeAuditEntry] {
        let path = Paths.normalized(rawPath)
        guard readPolicy.evaluate(path, checkSymlinks: true) == .allowed else {
            return []
        }

        guard let listResult = runGit(
            gitExecutable: gitExecutable,
            directory: path,
            args: ["worktree", "list", "--porcelain", "-z"],
            control: control
        ), listResult.status == 0, !listResult.timedOut else {
            return [
                WorktreeAuditEntry(
                    worktreePath: path,
                    repositoryRoot: path,
                    branchOrHead: "unknown",
                    isMainWorktree: true,
                    isLinkedWorktree: hasGitFileMarker(at: path),
                    status: .inspectionFailedUnknown,
                    usageVerified: false,
                    integrationEvidence: .unknown,
                    explanationES: "La consulta git worktree list falló o agotó el tiempo; estado desconocido (bloqueado).",
                    explanationEN: "git worktree list query failed or timed out; status unknown (blocked)."
                )
            ]
        }

        let records = parsePorcelainWorktreesZ(listResult.output)
        guard !records.isEmpty else {
            return [
                WorktreeAuditEntry(
                    worktreePath: path,
                    repositoryRoot: path,
                    branchOrHead: "unknown",
                    isMainWorktree: true,
                    isLinkedWorktree: hasGitFileMarker(at: path),
                    status: .inspectionFailedUnknown,
                    usageVerified: false,
                    integrationEvidence: .unknown,
                    explanationES: "Salida de git worktree list vacía o no reconocible; estado desconocido.",
                    explanationEN: "Empty or unrecognized git worktree list output; status unknown."
                )
            ]
        }

        let mainRoot = Paths.normalized(records[0].path)
        let defaultBranchRef = detectLocalDefaultBranch(gitExecutable: gitExecutable, directory: path, control: control)

        var results: [WorktreeAuditEntry] = []
        for (idx, record) in records.enumerated() {
            if control.shouldStop { break }
            let wtPath = Paths.normalized(record.path)
            let isMain = (idx == 0)
            let isLinked = !isMain || hasGitFileMarker(at: wtPath)
            let entry = inspectSingleWorktree(
                record: record,
                worktreePath: wtPath,
                repositoryRoot: mainRoot,
                isMainWorktree: isMain,
                isLinkedWorktree: isLinked,
                defaultBranchRef: defaultBranchRef,
                readPolicy: readPolicy,
                gitExecutable: gitExecutable,
                checkActiveProcesses: checkActiveProcesses,
                now: now,
                control: control
            )
            results.append(entry)
        }
        return results
    }

    private struct PorcelainWorktreeRecord {
        var path: String
        var headSHA: String?
        var branchRef: String?
        var isDetached: Bool = false
        var isBare: Bool = false
        var isLocked: Bool = false
        var lockReason: String?
        var isPrunable: Bool = false
    }

    private static func parsePorcelainWorktreesZ(_ output: String) -> [PorcelainWorktreeRecord] {
        // In `git worktree list --porcelain -z`, fields are NUL-separated and records are separated by an empty NUL token.
        let tokens = output.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        var records: [PorcelainWorktreeRecord] = []
        var current: PorcelainWorktreeRecord?

        for token in tokens {
            if token.isEmpty {
                if let rec = current {
                    records.append(rec)
                    current = nil
                }
                continue
            }
            if token.hasPrefix("worktree ") {
                if let rec = current {
                    records.append(rec)
                }
                let wtPath = String(token.dropFirst("worktree ".count))
                current = PorcelainWorktreeRecord(path: wtPath)
            } else if token.hasPrefix("HEAD ") {
                current?.headSHA = String(token.dropFirst("HEAD ".count))
            } else if token.hasPrefix("branch ") {
                current?.branchRef = String(token.dropFirst("branch ".count))
            } else if token == "detached" {
                current?.isDetached = true
            } else if token == "bare" {
                current?.isBare = true
            } else if token == "locked" {
                current?.isLocked = true
            } else if token.hasPrefix("locked ") {
                current?.isLocked = true
                current?.lockReason = String(token.dropFirst("locked ".count))
            } else if token == "prunable" || token.hasPrefix("prunable ") {
                current?.isPrunable = true
            }
        }
        if let rec = current {
            records.append(rec)
        }
        return records
    }

    private static func inspectSingleWorktree(
        record: PorcelainWorktreeRecord,
        worktreePath: String,
        repositoryRoot: String,
        isMainWorktree: Bool,
        isLinkedWorktree: Bool,
        defaultBranchRef: String?,
        readPolicy: ReadAuthorizationPolicy,
        gitExecutable: String,
        checkActiveProcesses: Bool,
        now: Date,
        control: ScanControl = ScanControl()
    ) -> WorktreeAuditEntry {
        let branchLabel: String = {
            if let branch = record.branchRef {
                return branch.replacingOccurrences(of: "refs/heads/", with: "")
            }
            if record.isDetached {
                let shortSHA = record.headSHA.map { String($0.prefix(7)) } ?? "HEAD"
                return "HEAD (\(shortSHA))"
            }
            return record.headSHA.map { String($0.prefix(7)) } ?? "unknown"
        }()

        guard !control.shouldStop, readPolicy.evaluate(worktreePath) == .allowed,
              !readPolicy.requiresUnauthedTCCPrompt(worktreePath) else {
            return WorktreeAuditEntry(worktreePath: worktreePath, repositoryRoot: repositoryRoot,
                branchOrHead: branchLabel, isMainWorktree: isMainWorktree,
                isLinkedWorktree: isLinkedWorktree, status: .inspectionFailedUnknown,
                usageVerified: false, integrationEvidence: .unknown,
                explanationES: "Consulta detenida o worktree fuera del alcance autorizado.",
                explanationEN: "Inspection stopped or worktree outside authorized scope.")
        }
        var st = stat()
        guard lstat(worktreePath, &st) == 0 else {
            if errno == ENOENT {
                return WorktreeAuditEntry(
                    worktreePath: worktreePath,
                    repositoryRoot: repositoryRoot,
                    branchOrHead: branchLabel,
                    headSHA: record.headSHA,
                    isMainWorktree: isMainWorktree,
                    isLinkedWorktree: isLinkedWorktree,
                    status: .staleMissingDirectory,
                    isLocked: record.isLocked,
                    lockReason: record.lockReason,
                    usageVerified: true,
                    integrationEvidence: .unknown,
                    explanationES: "Registro de worktree obsoleto (solo inventario): el directorio de trabajo ya no existe en disco.",
                    explanationEN: "Stale worktree metadata (inventory only): working directory no longer exists on disk."
                )
            }
            return WorktreeAuditEntry(
                worktreePath: worktreePath,
                repositoryRoot: repositoryRoot,
                branchOrHead: branchLabel,
                headSHA: record.headSHA,
                isMainWorktree: isMainWorktree,
                isLinkedWorktree: isLinkedWorktree,
                status: .inspectionFailedUnknown,
                isLocked: record.isLocked,
                lockReason: record.lockReason,
                usageVerified: false,
                integrationEvidence: .unknown,
                explanationES: "No se pudo acceder al directorio del worktree; estado desconocido.",
                explanationEN: "Could not access worktree directory; status unknown."
            )
        }

        guard readPolicy.evaluate(worktreePath, checkSymlinks: true) == .allowed else {
            return WorktreeAuditEntry(
                worktreePath: worktreePath,
                repositoryRoot: repositoryRoot,
                branchOrHead: branchLabel,
                headSHA: record.headSHA,
                isMainWorktree: isMainWorktree,
                isLinkedWorktree: isLinkedWorktree,
                status: .inspectionFailedUnknown,
                isLocked: record.isLocked,
                lockReason: record.lockReason,
                usageVerified: false,
                integrationEvidence: .unknown,
                explanationES: "Worktree fuera de las raíces de lectura autorizadas o con enlace simbólico; estado desconocido.",
                explanationEN: "Worktree outside authorized read roots or contains symbolic link; status unknown."
            )
        }

        // Measure size of the worktree safely
        var seenInodes = Set<InodeKey>()
        var examined = 0
        let measurement = StorageMeasurement.measure(
            path: worktreePath,
            category: .developerCaches,
            readPolicy: readPolicy,
            claimedPaths: [],
            neverTouchedPaths: [],
            seenInodes: &seenInodes,
            cancellation: control.cancellation,
            maxEntriesPerItem: 2_500,
            examinedCounter: &examined, deadline: control.deadline
        )
        let allocated = measurement?.allocatedBytes ?? 0
        let logical = measurement?.logicalBytes ?? 0

        // Check lock files inside git dir as well
        var isLocked = record.isLocked
        var lockReason = record.lockReason
        if let gitDirRes = runGit(gitExecutable: gitExecutable, directory: worktreePath, args: ["rev-parse", "--absolute-git-dir"], control: control),
           gitDirRes.status == 0, !gitDirRes.timedOut {
            let gitDir = gitDirRes.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if FileManager.default.fileExists(atPath: gitDir + "/locked") || FileManager.default.fileExists(atPath: gitDir + "/index.lock") {
                isLocked = true
                if lockReason == nil { lockReason = "index.lock / locked file present" }
            }
        }

        // 1. Check status --porcelain=v1 -z
        guard let statusRes = runGit(
            gitExecutable: gitExecutable,
            directory: worktreePath,
            args: ["status", "--porcelain=v1", "-z", "--untracked-files=all"],
            control: control
        ), statusRes.status == 0, !statusRes.timedOut else {
            return WorktreeAuditEntry(
                worktreePath: worktreePath,
                repositoryRoot: repositoryRoot,
                branchOrHead: branchLabel,
                headSHA: record.headSHA,
                isMainWorktree: isMainWorktree,
                isLinkedWorktree: isLinkedWorktree,
                status: .inspectionFailedUnknown,
                isLocked: isLocked,
                lockReason: lockReason,
                usageVerified: false,
                integrationEvidence: .unknown,
                allocatedBytes: allocated,
                logicalBytes: logical,
                explanationES: "La comprobación git status falló; no se asume que el worktree esté limpio.",
                explanationEN: "git status check failed; worktree is not assumed clean."
            )
        }
        let dirtyEntries = countPorcelainStatusZEntries(statusRes.output)

        // 2. Check unpushed local commits (`git rev-list --count HEAD --not --remotes`)
        var unpushedCount: Int? = nil
        if let revListRes = runGit(
            gitExecutable: gitExecutable,
            directory: worktreePath,
            args: ["rev-list", "--count", "HEAD", "--not", "--remotes"],
            control: control
        ), revListRes.status == 0, !revListRes.timedOut {
            unpushedCount = Int(revListRes.output.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            // If HEAD does not resolve or command fails, keep nil
            unpushedCount = nil
        }

        // 3. Check local integration evidence against local default branch (`main` / `master`) without fetching
        let integration: WorktreeIntegrationEvidence = {
            guard let defRef = defaultBranchRef, let headSHA = record.headSHA else {
                return .unknown
            }
            if record.branchRef == defRef {
                return .isDefaultBranch
            }
            guard let mbRes = runGit(
                gitExecutable: gitExecutable,
                directory: worktreePath,
                args: ["merge-base", "--is-ancestor", headSHA, defRef],
                control: control
            ), !mbRes.timedOut else {
                return .unknown
            }
            if mbRes.status == 0 {
                return .mergedIntoDefaultBranch
            } else if mbRes.status == 1 {
                return .notMergedIntoDefaultBranch
            }
            return .unknown
        }()

        // 4. Check active processes (CWD or open descriptors) via lsof if enabled
        var activePIDs: [Int32] = []
        var usageVerified = false
        if checkActiveProcesses {
            if let pids = queryDirectoryProcesses(path: worktreePath, control: control) {
                activePIDs = pids
                usageVerified = true
            } else {
                usageVerified = false
            }
        }

        let modTime = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9
        let recentlyModified = (now.timeIntervalSince1970 - modTime) < 3_600 // modified within last hour

        // Determine final conservative status
        let finalStatus: WorktreeAuditStatus
        let explanationES: String
        let explanationEN: String

        if isLocked {
            finalStatus = .locked
            explanationES = "Worktree bloqueado (\(lockReason ?? "locked")); solo inventario."
            explanationEN = "Locked worktree (\(lockReason ?? "locked")); inventory only."
        } else if !activePIDs.isEmpty {
            finalStatus = .inUseProcess
            explanationES = "Worktree en uso por procesos activos (PID: \(activePIDs.map(String.init).joined(separator: ", "))); solo inventario."
            explanationEN = "Worktree in use by active processes (PID: \(activePIDs.map(String.init).joined(separator: ", "))); inventory only."
        } else if dirtyEntries > 0 {
            finalStatus = .dirtyUncommitted
            explanationES = "Contiene \(dirtyEntries) cambio(s) sin confirmar o archivos sin seguimiento; protegido en modo inventario."
            explanationEN = "Contains \(dirtyEntries) uncommitted or untracked change(s); protected in inventory mode."
        } else if let unpushed = unpushedCount, unpushed > 0 && integration != .mergedIntoDefaultBranch {
            finalStatus = .unpushedCommits
            explanationES = "Contiene \(unpushed) commit(s) locales no publicados en remotos ni integrados en la rama principal; protegido."
            explanationEN = "Contains \(unpushed) local commit(s) not pushed to remotes or merged into the default branch; protected."
        } else if checkActiveProcesses && !usageVerified {
            finalStatus = .inspectionFailedUnknown
            explanationES = "No se pudo verificar mediante lsof si hay procesos usando el worktree; estado desconocido."
            explanationEN = "Could not verify via lsof whether processes are using the worktree; status unknown."
        } else if recentlyModified {
            finalStatus = .recentlyModified
            explanationES = "Worktree limpio pero modificado recientemente (< 1 h); mantenido en inventario."
            explanationEN = "Clean worktree modified recently (< 1h); kept in inventory."
        } else {
            finalStatus = .cleanIdle
            let mergeNoteES = integration == .mergedIntoDefaultBranch
                ? "integrado localmente en la rama principal"
                : "sin evidencia de integración completa"
            let mergeNoteEN = integration == .mergedIntoDefaultBranch
                ? "merged locally into default branch"
                : "without proven full integration"
            explanationES = "Worktree limpio e inactivo (\(mergeNoteES)); visible en modo inventario sin borrado automático."
            explanationEN = "Clean idle worktree (\(mergeNoteEN)); shown in inventory mode without automatic deletion."
        }

        return WorktreeAuditEntry(
            worktreePath: worktreePath,
            repositoryRoot: repositoryRoot,
            branchOrHead: branchLabel,
            headSHA: record.headSHA,
            isMainWorktree: isMainWorktree,
            isLinkedWorktree: isLinkedWorktree,
            status: finalStatus,
            dirtyCount: dirtyEntries,
            unpushedCommitCount: unpushedCount,
            isLocked: isLocked,
            lockReason: lockReason,
            activeProcessPIDs: activePIDs,
            usageVerified: usageVerified,
            integrationEvidence: integration,
            allocatedBytes: allocated,
            logicalBytes: logical,
            explanationES: explanationES,
            explanationEN: explanationEN
        )
    }

    // MARK: - Project Contextual Build Artifacts

    private struct ProjectArtifactRule {
        let directoryName: String
        let anchorFiles: [String]
        let ecosystem: String
        let regenerableReasonES: String
        let regenerableReasonEN: String
        let rebuildRequirementsES: String
        let rebuildRequirementsEN: String
        let rebuildCommand: String
        let compilerProcessNames: [String]
    }

    private static let artifactRules: [ProjectArtifactRule] = [
        ProjectArtifactRule(
            directoryName: ".build",
            anchorFiles: ["Package.swift"],
            ecosystem: "SwiftPM",
            regenerableReasonES: "Compilación y descargas resueltas de Swift Package Manager derivadas de Package.swift y Package.resolved.",
            regenerableReasonEN: "Swift Package Manager build outputs and resolved checkouts derived from Package.swift and Package.resolved.",
            rebuildRequirementsES: "Requiere Xcode/Swift toolchain y acceso a dependencias remotas si no están cacheadas.",
            rebuildRequirementsEN: "Requires Xcode/Swift toolchain and network access for uncached package dependencies.",
            rebuildCommand: "swift build",
            compilerProcessNames: ["swift-frontend", "swift-build", "swiftc", "xcodebuild"]
        ),
        ProjectArtifactRule(
            directoryName: "target",
            anchorFiles: ["Cargo.toml", "pom.xml"],
            ecosystem: "Rust / Maven",
            regenerableReasonES: "Artefactos compilados intermedios y binarios generados a partir del código fuente y Cargo.toml / pom.xml.",
            regenerableReasonEN: "Compiled intermediate crates/classes and binaries generated from source code and Cargo.toml / pom.xml.",
            rebuildRequirementsES: "Requiere Rust (cargo/rustc) o JDK/Maven según el manifiesto del proyecto.",
            rebuildRequirementsEN: "Requires Rust (cargo/rustc) or JDK/Maven matching the project manifest.",
            rebuildCommand: "cargo build / mvn compile",
            compilerProcessNames: ["cargo", "rustc", "mvn", "java"]
        ),
        ProjectArtifactRule(
            directoryName: "node_modules",
            anchorFiles: ["package.json"],
            ecosystem: "Node.js",
            regenerableReasonES: "Dependencias instaladas localmente desde package.json y el lockfile (package-lock.json, pnpm-lock.yaml o yarn.lock).",
            regenerableReasonEN: "Installed local dependencies resolved from package.json and lockfile (package-lock.json, pnpm-lock.yaml, or yarn.lock).",
            rebuildRequirementsES: "Requiere Node.js, tu gestor de paquetes y acceso al registro o caché local.",
            rebuildRequirementsEN: "Requires Node.js, your package manager, and registry or local cache availability.",
            rebuildCommand: "npm ci / pnpm install --frozen-lockfile / yarn install",
            compilerProcessNames: ["npm", "pnpm", "yarn", "tsc", "vite", "webpack", "esbuild"]
        ),
        ProjectArtifactRule(
            directoryName: ".next",
            anchorFiles: ["package.json"],
            ecosystem: "Next.js",
            regenerableReasonES: "Salida de compilación y caché de rutas de Next.js regenerable desde el código fuente.",
            regenerableReasonEN: "Next.js build output and route cache regenerable from project source.",
            rebuildRequirementsES: "Requiere Node.js y node_modules instalado en el proyecto.",
            rebuildRequirementsEN: "Requires Node.js and project dependencies installed in node_modules.",
            rebuildCommand: "npm run build",
            compilerProcessNames: ["next-server", "node", "webpack", "turbopack"]
        ),
        ProjectArtifactRule(
            directoryName: ".nuxt",
            anchorFiles: ["package.json"],
            ecosystem: "Nuxt",
            regenerableReasonES: "Tipos y artefactos temporales generados por Nuxt.",
            regenerableReasonEN: "Generated Nuxt types and temporary build artifacts.",
            rebuildRequirementsES: "Requiere Node.js y node_modules instalado en el proyecto.",
            rebuildRequirementsEN: "Requires Node.js and installed project dependencies.",
            rebuildCommand: "npx nuxi prepare && npm run build",
            compilerProcessNames: ["node", "vite", "nuxt"]
        ),
        ProjectArtifactRule(
            directoryName: ".svelte-kit",
            anchorFiles: ["package.json"],
            ecosystem: "SvelteKit",
            regenerableReasonES: "Manifiestos y compilación generada por SvelteKit.",
            regenerableReasonEN: "SvelteKit generated manifests and build intermediates.",
            rebuildRequirementsES: "Requiere Node.js y node_modules instalado en el proyecto.",
            rebuildRequirementsEN: "Requires Node.js and installed project dependencies.",
            rebuildCommand: "npx svelte-kit sync && npm run build",
            compilerProcessNames: ["node", "vite"]
        ),
        ProjectArtifactRule(
            directoryName: ".turbo",
            anchorFiles: ["package.json"],
            ecosystem: "Turborepo",
            regenerableReasonES: "Caché local de tareas de Turborepo.",
            regenerableReasonEN: "Local Turborepo task cache.",
            rebuildRequirementsES: "Requiere ejecutar de nuevo las tareas del monorepo.",
            rebuildRequirementsEN: "Rebuilt on next monorepo task run.",
            rebuildCommand: "npx turbo run build",
            compilerProcessNames: ["turbo", "node"]
        ),
        ProjectArtifactRule(
            directoryName: ".parcel-cache",
            anchorFiles: ["package.json"],
            ecosystem: "Parcel",
            regenerableReasonES: "Caché incremental del empaquetador Parcel.",
            regenerableReasonEN: "Incremental Parcel bundler cache.",
            rebuildRequirementsES: "Se regenera al volver a empaquetar con Parcel.",
            rebuildRequirementsEN: "Regenerated on next Parcel build.",
            rebuildCommand: "npx parcel build",
            compilerProcessNames: ["parcel", "node"]
        ),
        ProjectArtifactRule(
            directoryName: ".angular",
            anchorFiles: ["package.json"],
            ecosystem: "Angular",
            regenerableReasonES: "Caché persistente de compilación de Angular CLI.",
            regenerableReasonEN: "Angular CLI persistent build cache.",
            rebuildRequirementsES: "Requiere Angular CLI y dependencias instaladas.",
            rebuildRequirementsEN: "Requires Angular CLI and installed dependencies.",
            rebuildCommand: "npx ng build",
            compilerProcessNames: ["ng", "node"]
        ),
        ProjectArtifactRule(
            directoryName: "dist",
            anchorFiles: ["package.json"],
            ecosystem: "JavaScript / TypeScript",
            regenerableReasonES: "Salida empaquetada o transpilada (no rastreada por Git) del proyecto JS/TS.",
            regenerableReasonEN: "Compiled or bundled distribution output (untracked by Git) for JS/TS project.",
            rebuildRequirementsES: "Requiere dependencias instaladas y ejecutar el script de build del proyecto.",
            rebuildRequirementsEN: "Requires installed dependencies and running the project's build script.",
            rebuildCommand: "npm run build",
            compilerProcessNames: ["tsc", "vite", "webpack", "esbuild", "rollup"]
        ),
        ProjectArtifactRule(
            directoryName: "build",
            anchorFiles: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts", "package.json", "CMakeLists.txt"],
            ecosystem: "Gradle / JS / CMake",
            regenerableReasonES: "Directorio de salida compilada generado por Gradle, CMake o script JS/TS.",
            regenerableReasonEN: "Compiled build output directory generated by Gradle, CMake, or JS/TS tooling.",
            rebuildRequirementsES: "Requiere Gradle/JDK, CMake/compilador o entorno Node según el manifiesto.",
            rebuildRequirementsEN: "Requires Gradle/JDK, CMake toolchain, or Node environment matching project manifest.",
            rebuildCommand: "./gradlew build / cmake --build build",
            compilerProcessNames: ["gradle", "java", "kotlinc", "cmake", "ninja", "clang"]
        ),
        ProjectArtifactRule(
            directoryName: ".gradle",
            anchorFiles: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"],
            ecosystem: "Gradle",
            regenerableReasonES: "Caché local por proyecto de Gradle (estado de tareas y transformaciones).",
            regenerableReasonEN: "Per-project Gradle task and build cache.",
            rebuildRequirementsES: "Se reconstruye en la siguiente ejecución de Gradle.",
            rebuildRequirementsEN: "Reconstructed automatically on next Gradle run.",
            rebuildCommand: "./gradlew build",
            compilerProcessNames: ["gradle", "java", "kotlinc"]
        ),
        ProjectArtifactRule(
            directoryName: ".cxx",
            anchorFiles: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"],
            ecosystem: "Android NDK / Gradle",
            regenerableReasonES: "Artefactos nativos C/C++ generados por Android NDK y CMake.",
            regenerableReasonEN: "Native C/C++ intermediates generated by Android NDK and CMake.",
            rebuildRequirementsES: "Requiere Android NDK y Gradle configurado.",
            rebuildRequirementsEN: "Requires Android NDK and Gradle configuration.",
            rebuildCommand: "./gradlew assembleDebug",
            compilerProcessNames: ["cmake", "ninja", "clang++", "gradle"]
        ),
        ProjectArtifactRule(
            directoryName: ".kotlin",
            anchorFiles: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"],
            ecosystem: "Kotlin / Gradle",
            regenerableReasonES: "Caché incremental del compilador Kotlin dentro del proyecto.",
            regenerableReasonEN: "Incremental Kotlin compiler cache stored inside the project.",
            rebuildRequirementsES: "Se regenera al compilar de nuevo con Gradle.",
            rebuildRequirementsEN: "Regenerated on next Kotlin/Gradle compilation.",
            rebuildCommand: "./gradlew compileKotlin",
            compilerProcessNames: ["kotlinc", "gradle", "java"]
        ),
        ProjectArtifactRule(
            directoryName: "Pods",
            anchorFiles: ["Podfile"],
            ecosystem: "CocoaPods",
            regenerableReasonES: "Dependencias iOS/macOS descargadas por CocoaPods desde Podfile y Podfile.lock.",
            regenerableReasonEN: "iOS/macOS dependencies resolved by CocoaPods from Podfile and Podfile.lock.",
            rebuildRequirementsES: "Requiere CocoaPods (`pod`) y acceso a los repositorios de pods.",
            rebuildRequirementsEN: "Requires CocoaPods (`pod`) and access to pod repositories.",
            rebuildCommand: "pod install",
            compilerProcessNames: ["pod", "xcodebuild"]
        ),
        ProjectArtifactRule(
            directoryName: ".venv",
            anchorFiles: ["pyproject.toml", "requirements.txt", "setup.py"],
            ecosystem: "Python virtualenv",
            regenerableReasonES: "Entorno virtual Python recreable a partir del intérprete y manifiesto/lockfile.",
            regenerableReasonEN: "Python virtual environment recreatable from Python interpreter and project manifest.",
            rebuildRequirementsES: "Requiere Python compatible y reinstalar dependencias (`pip`/`uv`).",
            rebuildRequirementsEN: "Requires matching Python version and reinstalling packages (`pip`/`uv`).",
            rebuildCommand: "python3 -m venv .venv && .venv/bin/pip install -r requirements.txt",
            compilerProcessNames: ["python", "python3", "pip", "uv"]
        ),
        ProjectArtifactRule(
            directoryName: ".pytest_cache",
            anchorFiles: ["pyproject.toml", "requirements.txt", "setup.py"],
            ecosystem: "pytest",
            regenerableReasonES: "Caché local de ejecución de pruebas de pytest.",
            regenerableReasonEN: "Local pytest test runner cache.",
            rebuildRequirementsES: "Se regenera automáticamente al ejecutar pytest.",
            rebuildRequirementsEN: "Automatically regenerated when running pytest.",
            rebuildCommand: "pytest",
            compilerProcessNames: ["pytest", "python3"]
        ),
        ProjectArtifactRule(
            directoryName: ".mypy_cache",
            anchorFiles: ["pyproject.toml", "requirements.txt", "setup.py"],
            ecosystem: "mypy",
            regenerableReasonES: "Caché incremental de verificación de tipos de mypy.",
            regenerableReasonEN: "Incremental mypy type-checking cache.",
            rebuildRequirementsES: "Se regenera automáticamente al ejecutar mypy.",
            rebuildRequirementsEN: "Automatically regenerated when running mypy.",
            rebuildCommand: "mypy .",
            compilerProcessNames: ["mypy", "python3"]
        ),
        ProjectArtifactRule(
            directoryName: ".ruff_cache",
            anchorFiles: ["pyproject.toml", "requirements.txt", "setup.py"],
            ecosystem: "Ruff",
            regenerableReasonES: "Caché local del linter/formateador Ruff.",
            regenerableReasonEN: "Local Ruff linter/formatter cache.",
            rebuildRequirementsES: "Se regenera automáticamente al ejecutar ruff.",
            rebuildRequirementsEN: "Automatically regenerated when running ruff.",
            rebuildCommand: "ruff check .",
            compilerProcessNames: ["ruff"]
        ),
        ProjectArtifactRule(
            directoryName: "_build",
            anchorFiles: ["mix.exs"],
            ecosystem: "Elixir Mix",
            regenerableReasonES: "Artefactos compilados BEAM generados por Mix.",
            regenerableReasonEN: "Compiled BEAM artifacts generated by Elixir Mix.",
            rebuildRequirementsES: "Requiere Elixir/Erlang y recompilar con Mix.",
            rebuildRequirementsEN: "Requires Elixir/Erlang and recompiling via Mix.",
            rebuildCommand: "mix compile",
            compilerProcessNames: ["beam.smp", "mix"]
        ),
        ProjectArtifactRule(
            directoryName: ".dart_tool",
            anchorFiles: ["pubspec.yaml"],
            ecosystem: "Dart / Flutter",
            regenerableReasonES: "Configuración generada de paquetes y compilación temporal de Dart/Flutter.",
            regenerableReasonEN: "Generated Dart/Flutter package resolution config and build intermediates.",
            rebuildRequirementsES: "Requiere SDK de Dart/Flutter para volver a resolver pubspec.",
            rebuildRequirementsEN: "Requires Dart/Flutter SDK to resolve pubspec again.",
            rebuildCommand: "dart pub get",
            compilerProcessNames: ["dart", "flutter"]
        )
    ]

    private static let rulesByDirName: [String: [ProjectArtifactRule]] = Dictionary(grouping: artifactRules, by: \.directoryName)

    private static func findRule(directoryName: String, anchorFile: String, ecosystem: String) -> ProjectArtifactRule? {
        let candidates = rulesByDirName[directoryName] ?? []
        return candidates.first { $0.anchorFiles.contains(anchorFile) }
            ?? candidates.first { $0.ecosystem == ecosystem }
            ?? candidates.first
    }

    /// Discovers project-anchored build/dependency directories under authorized roots and verifies Git tracking,
    /// subrepository status, symlinks, and active usage. Always returns inventory-only entries.
    public static func scanProjectArtifacts(
        authorizedRoots: [String],
        readPolicy: ReadAuthorizationPolicy,
        maxDepth: Int = 5,
        maxVisitedDirectories: Int = 2_500,
        maxVisitedEntries: Int = 50_000,
        gitExecutable: String = "/usr/bin/git",
        checkActiveProcesses: Bool = true,
        now: Date = Date(),
        control: ScanControl = ScanControl(),
        maxEntriesPerArtifact: Int = 2_500
    ) -> [ProjectArtifactAuditEntry] {
        let walked = walkAuthorizedDirectories(
            authorizedRoots: authorizedRoots,
            readPolicy: readPolicy,
            maxDepth: maxDepth,
            maxVisitedDirectories: maxVisitedDirectories,
            maxVisitedEntries: maxVisitedEntries,
            collectGitRoots: false,
            collectArtifacts: true,
            gitExecutable: gitExecutable,
            checkActiveProcesses: checkActiveProcesses,
            now: now,
            control: control,
            maxEntriesPerArtifact: maxEntriesPerArtifact
        )
        return walked.artifacts.sorted { $0.artifactPath < $1.artifactPath }
    }

    public static func inspectSingleProjectArtifact(
        artifactPath rawArtifactPath: String,
        artifactName: String,
        projectRoot rawProjectRoot: String,
        anchorFile: String,
        ecosystem: String,
        readPolicy: ReadAuthorizationPolicy,
        gitExecutable: String = "/usr/bin/git",
        checkActiveProcesses: Bool = true,
        now: Date = Date(),
        control: ScanControl = ScanControl(),
        maxEntriesPerArtifact: Int = 2_500
    ) -> ProjectArtifactAuditEntry {
        let artifactPath = Paths.normalized(rawArtifactPath)
        let projectRoot = Paths.normalized(rawProjectRoot)
        let rule = findRule(directoryName: artifactName, anchorFile: anchorFile, ecosystem: ecosystem)
        let regenES = rule?.regenerableReasonES ?? "Artefacto generado del proyecto reconstruible desde su manifiesto."
        let regenEN = rule?.regenerableReasonEN ?? "Generated project artifact rebuildable from project manifest."
        let reqES = rule?.rebuildRequirementsES ?? "Requiere la cadena de herramientas del ecosistema \(ecosystem)."
        let reqEN = rule?.rebuildRequirementsEN ?? "Requires the \(ecosystem) toolchain."
        let rebuildCmd = rule?.rebuildCommand ?? ""

        var st = stat()
        guard lstat(artifactPath, &st) == 0 else {
            return ProjectArtifactAuditEntry(
                artifactPath: artifactPath,
                artifactName: artifactName,
                projectRoot: projectRoot,
                anchorFile: anchorFile,
                ecosystem: ecosystem,
                state: .blockedUnverifiedGitOrUsage,
                regenerableReasonES: regenES,
                regenerableReasonEN: regenEN,
                rebuildRequirementsES: reqES,
                rebuildRequirementsEN: reqEN,
                rebuildCommand: rebuildCmd,
                usageUncertaintyES: "No se pudo consultar el estado del directorio en disco.",
                usageUncertaintyEN: "Could not inspect artifact directory on disk.",
                explanationES: "No se pudo inspeccionar el directorio del artefacto.",
                explanationEN: "Could not inspect artifact directory."
            )
        }

        let dirModTime = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9
        let modifiedAt = Date(timeIntervalSince1970: dirModTime)
        let identity = SafetyPolicy.identity(st)

        // 1. Direct symlink check
        if (st.st_mode & S_IFMT) == S_IFLNK {
            return ProjectArtifactAuditEntry(
                artifactPath: artifactPath,
                artifactName: artifactName,
                projectRoot: projectRoot,
                anchorFile: anchorFile,
                ecosystem: ecosystem,
                state: .blockedContainsSymlink,
                containsSymlink: true,
                modifiedAt: modifiedAt,
                identity: identity,
                regenerableReasonES: regenES,
                regenerableReasonEN: regenEN,
                rebuildRequirementsES: reqES,
                rebuildRequirementsEN: reqEN,
                rebuildCommand: rebuildCmd,
                usageUncertaintyES: "Enlace simbólico directo; destino externo protegido.",
                usageUncertaintyEN: "Direct symbolic link; external target is protected.",
                explanationES: "Bloqueado (solo inventario): \(artifactName) es un enlace simbólico.",
                explanationEN: "Blocked (inventory only): \(artifactName) is a symbolic link."
            )
        }

        // 2. Measure and check nested symlinks or nested `.git`
        var seenInodes = Set<InodeKey>()
        var examined = 0
        let measurement = StorageMeasurement.measure(
            path: artifactPath,
            category: .developerCaches,
            readPolicy: readPolicy,
            claimedPaths: [],
            neverTouchedPaths: [],
            seenInodes: &seenInodes,
            cancellation: control.cancellation,
            maxEntriesPerItem: maxEntriesPerArtifact,
            examinedCounter: &examined, deadline: control.deadline
        )
        let allocated = measurement?.allocatedBytes ?? 0
        let logical = measurement?.logicalBytes ?? 0
        let latestChildModifiedAt = measurement?.modifiedAt
        let hasSymlinkInside = measurement?.containsSymlink ?? false
        if measurement == nil || measurement?.isPartial == true || measurement?.skippedProtectedChild == true {
            return ProjectArtifactAuditEntry(artifactPath: artifactPath, artifactName: artifactName,
                projectRoot: projectRoot, anchorFile: anchorFile, ecosystem: ecosystem,
                state: .blockedUnverifiedGitOrUsage, containsSymlink: hasSymlinkInside,
                allocatedBytes: allocated, logicalBytes: logical,
                modifiedAt: modifiedAt, latestChildModifiedAt: latestChildModifiedAt, identity: identity,
                regenerableReasonES: regenES, regenerableReasonEN: regenEN,
                rebuildRequirementsES: reqES, rebuildRequirementsEN: reqEN,
                rebuildCommand: rebuildCmd,
                usageUncertaintyES: "Inspección parcial o vacía; falta verificación completa del contenido.",
                usageUncertaintyEN: "Partial or empty measurement; full tree verification incomplete.",
                explanationES: "Inspección parcial; no se ha verificado todo el árbol del artefacto.",
                explanationEN: "Partial inspection; the complete artifact tree has not been verified.")
        }

        if hasSymlinkInside {
            return ProjectArtifactAuditEntry(
                artifactPath: artifactPath,
                artifactName: artifactName,
                projectRoot: projectRoot,
                anchorFile: anchorFile,
                ecosystem: ecosystem,
                state: .blockedContainsSymlink,
                containsSymlink: true,
                allocatedBytes: allocated,
                logicalBytes: logical,
                modifiedAt: modifiedAt,
                latestChildModifiedAt: latestChildModifiedAt,
                identity: identity,
                regenerableReasonES: regenES,
                regenerableReasonEN: regenEN,
                rebuildRequirementsES: reqES,
                rebuildRequirementsEN: reqEN,
                rebuildCommand: rebuildCmd,
                usageUncertaintyES: "Contiene enlaces simbólicos internos que impiden limpieza automática segura.",
                usageUncertaintyEN: "Contains internal symbolic links preventing safe cleanup.",
                explanationES: "Bloqueado (solo inventario): \(artifactName) contiene enlaces simbólicos internos.",
                explanationEN: "Blocked (inventory only): \(artifactName) contains internal symbolic links."
            )
        }

        // 3. Check if artifact is itself a nested Git subrepository
        var nestedGitStat = stat()
        let hasNestedGit = (measurement?.containsNestedGit ?? false) || lstat(artifactPath + "/.git", &nestedGitStat) == 0
        if hasNestedGit {
            return ProjectArtifactAuditEntry(
                artifactPath: artifactPath,
                artifactName: artifactName,
                projectRoot: projectRoot,
                anchorFile: anchorFile,
                ecosystem: ecosystem,
                state: .blockedNestedSubrepository,
                containsSymlink: hasSymlinkInside,
                isNestedSubrepository: true,
                allocatedBytes: allocated,
                logicalBytes: logical,
                modifiedAt: modifiedAt,
                latestChildModifiedAt: latestChildModifiedAt,
                identity: identity,
                regenerableReasonES: regenES,
                regenerableReasonEN: regenEN,
                rebuildRequirementsES: reqES,
                rebuildRequirementsEN: reqEN,
                rebuildCommand: rebuildCmd,
                usageUncertaintyES: "Contiene un subrepositorio Git independiente (.git).",
                usageUncertaintyEN: "Contains its own nested Git repository (.git).",
                explanationES: "Bloqueado (solo inventario): \(artifactName) contiene un subrepositorio Git propio.",
                explanationEN: "Blocked (inventory only): \(artifactName) contains its own nested Git repository."
            )
        }

        // 4. Check if projectRoot is inside a Git repo and whether files in artifactName are tracked (`git ls-files -z`)
        var trackedCount: Int? = nil
        var gitVerified = false
        if let topRes = runGit(gitExecutable: gitExecutable, directory: projectRoot, args: ["rev-parse", "--show-toplevel"], control: control),
           topRes.status == 0, !topRes.timedOut {
            if let lsRes = runGit(
                gitExecutable: gitExecutable,
                directory: projectRoot,
                args: ["ls-files", "-z", "--", artifactName],
                control: control
            ), lsRes.status == 0, !lsRes.timedOut {
                let tracked = lsRes.output.split(separator: "\0", omittingEmptySubsequences: true)
                trackedCount = tracked.count
                gitVerified = true
            } else {
                gitVerified = false
            }
        } else if let res = runGit(gitExecutable: gitExecutable, directory: projectRoot,
                                   args: ["rev-parse", "--is-inside-work-tree"], control: control),
                  !res.timedOut, res.status == 128, res.error.contains("not a git repository") {
            gitVerified = true
            trackedCount = 0
        }

        if let tracked = trackedCount, tracked > 0 {
            return ProjectArtifactAuditEntry(
                artifactPath: artifactPath,
                artifactName: artifactName,
                projectRoot: projectRoot,
                anchorFile: anchorFile,
                ecosystem: ecosystem,
                state: .blockedTrackedByGit,
                trackedFileCount: tracked,
                containsSymlink: hasSymlinkInside,
                allocatedBytes: allocated,
                logicalBytes: logical,
                modifiedAt: modifiedAt,
                latestChildModifiedAt: latestChildModifiedAt,
                identity: identity,
                regenerableReasonES: regenES,
                regenerableReasonEN: regenEN,
                rebuildRequirementsES: reqES,
                rebuildRequirementsEN: reqEN,
                rebuildCommand: rebuildCmd,
                usageUncertaintyES: "Git rastrea archivos dentro de este directorio; no es una salida puramente derivada.",
                usageUncertaintyEN: "Git tracks files inside this directory; it is not purely derived output.",
                explanationES: "Bloqueado (solo inventario): Git rastrea \(tracked) archivo(s) dentro de \(artifactName) (p. ej. dependencias vendorizadas o distribución versionada).",
                explanationEN: "Blocked (inventory only): Git tracks \(tracked) file(s) inside \(artifactName) (e.g., vendored dependencies or versioned distribution)."
            )
        }

        // 5. Check active usage via lsof + modification recency + optional ecosystem compiler warnings
        var activePIDs: [Int32] = []
        var usageVerified = !checkActiveProcesses
        var buildWarnings: [String] = []
        if checkActiveProcesses {
            if let pids = queryDirectoryProcesses(path: artifactPath, control: control) {
                activePIDs = pids
                usageVerified = true
            } else {
                usageVerified = false
            }
            if let processes = try? ProcessInspector.list(control: control), let compilerNames = rule?.compilerProcessNames {
                let activeNames = Set(processes.map { URL(fileURLWithPath: $0.executable).lastPathComponent })
                buildWarnings = compilerNames.filter { activeNames.contains($0) }
            }
        }

        if !gitVerified || !usageVerified {
            return ProjectArtifactAuditEntry(
                artifactPath: artifactPath,
                artifactName: artifactName,
                projectRoot: projectRoot,
                anchorFile: anchorFile,
                ecosystem: ecosystem,
                state: .blockedUnverifiedGitOrUsage,
                trackedFileCount: trackedCount,
                containsSymlink: hasSymlinkInside,
                activeProcessPIDs: activePIDs,
                usageVerified: usageVerified,
                allocatedBytes: allocated,
                logicalBytes: logical,
                modifiedAt: modifiedAt,
                latestChildModifiedAt: latestChildModifiedAt,
                identity: identity,
                regenerableReasonES: regenES,
                regenerableReasonEN: regenEN,
                rebuildRequirementsES: reqES,
                rebuildRequirementsEN: reqEN,
                rebuildCommand: rebuildCmd,
                activeBuildWarnings: buildWarnings,
                usageUncertaintyES: !gitVerified
                    ? "No se pudo verificar el estado de Git; origen sin confirmar."
                    : "No se pudo confirmar uso activo con lsof; incertidumbre bloqueante.",
                usageUncertaintyEN: !gitVerified
                    ? "Could not verify Git tracking state; origin unconfirmed."
                    : "Could not verify open handles via lsof; blocked on uncertainty.",
                explanationES: "Estado de Git o de uso activo sin verificar; mantenido como inventario bloqueado.",
                explanationEN: "Unverified Git tracking or process usage state; kept as blocked inventory."
            )
        }

        let isRecent = (now.timeIntervalSince1970 - dirModTime) < 3_600

        if !activePIDs.isEmpty || isRecent {
            let uncertES = !activePIDs.isEmpty
                ? "Procesos activos (\(activePIDs.map(String.init).joined(separator: ", "))) con archivos abiertos en el artefacto."
                : "Directorio modificado hace menos de 60 minutos (la fecha de modificación refleja escrituras recientes, no uso futuro)."
            let uncertEN = !activePIDs.isEmpty
                ? "Active processes (\(activePIDs.map(String.init).joined(separator: ", "))) hold open files inside this artifact."
                : "Directory modified under 60 minutes ago (mtime reflects recent filesystem activity, not future reuse)."
            return ProjectArtifactAuditEntry(
                artifactPath: artifactPath,
                artifactName: artifactName,
                projectRoot: projectRoot,
                anchorFile: anchorFile,
                ecosystem: ecosystem,
                state: .blockedActiveOrRecent,
                trackedFileCount: trackedCount,
                containsSymlink: hasSymlinkInside,
                activeProcessPIDs: activePIDs,
                usageVerified: usageVerified,
                allocatedBytes: allocated,
                logicalBytes: logical,
                modifiedAt: modifiedAt,
                latestChildModifiedAt: latestChildModifiedAt,
                identity: identity,
                regenerableReasonES: regenES,
                regenerableReasonEN: regenEN,
                rebuildRequirementsES: reqES,
                rebuildRequirementsEN: reqEN,
                rebuildCommand: rebuildCmd,
                activeBuildWarnings: buildWarnings,
                usageUncertaintyES: uncertES,
                usageUncertaintyEN: uncertEN,
                explanationES: "Proyecto activo o modificado recientemente; artefacto (\(artifactName) · \(anchorFile)) conservado en inventario.",
                explanationEN: "Active or recently modified project; artifact (\(artifactName) · \(anchorFile)) kept in inventory."
            )
        }

        let uncertES: String
        let uncertEN: String
        if !buildWarnings.isEmpty {
            let joined = buildWarnings.joined(separator: ", ")
            uncertES = "Sin archivos abiertos vía lsof, pero hay procesos del ecosistema en ejecución (\(joined)); la fecha de modificación no prueba el último uso humano."
            uncertEN = "No open handles via lsof, though ecosystem processes are running (\(joined)); mtime does not prove last human use."
        } else if !checkActiveProcesses {
            uncertES = "Comprobación de procesos desactivada en este escaneo; la fecha de modificación no demuestra cuándo se usó por última vez."
            uncertEN = "Active process check was skipped for this scan; mtime does not prove when the project was last used."
        } else {
            uncertES = "Sin archivos abiertos con lsof en este instante; un proceso detenido o futuro puede requerir reconstrucción y mtime no equivale a último uso."
            uncertEN = "No open file handles via lsof at check time; a paused workflow may need rebuild and mtime is not proof of last use."
        }

        return ProjectArtifactAuditEntry(
            artifactPath: artifactPath,
            artifactName: artifactName,
            projectRoot: projectRoot,
            anchorFile: anchorFile,
            ecosystem: ecosystem,
            state: .anchoredIdleCandidate,
            trackedFileCount: trackedCount ?? 0,
            containsSymlink: hasSymlinkInside,
            activeProcessPIDs: [],
            usageVerified: usageVerified,
            allocatedBytes: allocated,
            logicalBytes: logical,
            modifiedAt: modifiedAt,
            latestChildModifiedAt: latestChildModifiedAt,
            identity: identity,
            regenerableReasonES: regenES,
            regenerableReasonEN: regenEN,
            rebuildRequirementsES: reqES,
            rebuildRequirementsEN: reqEN,
            rebuildCommand: rebuildCmd,
            activeBuildWarnings: buildWarnings,
            usageUncertaintyES: uncertES,
            usageUncertaintyEN: uncertEN,
            explanationES: "Artefacto de proyecto (\(ecosystem), ancla \(anchorFile)) sin archivos rastreados ni procesos activos; listado en modo inventario.",
            explanationEN: "Project artifact (\(ecosystem), anchor \(anchorFile)) with no tracked files or active processes; listed in inventory mode."
        )
    }

    // MARK: - Helpers

    private struct DirectoryWalkResult {
        var repoRoots: [String] = []
        var artifacts: [ProjectArtifactAuditEntry] = []
    }

    private static func walkAuthorizedDirectories(
        authorizedRoots: [String],
        readPolicy: ReadAuthorizationPolicy,
        maxDepth: Int,
        maxVisitedDirectories: Int,
        maxVisitedEntries: Int,
        collectGitRoots: Bool,
        collectArtifacts: Bool,
        gitExecutable: String,
        checkActiveProcesses: Bool,
        now: Date,
        control: ScanControl = ScanControl(),
        maxEntriesPerArtifact: Int = 2_500
    ) -> DirectoryWalkResult {
        var result = DirectoryWalkResult()
        var seenRepoRoots = Set<String>()
        var seenArtifactPaths = Set<String>()
        var visitedDirs = 0
        var visitedEntries = 0

        func recordCoverage(_ gitReason: String, _ projectReason: String) {
            if collectGitRoots { control.coverage.record(gitReason) }
            if collectArtifacts { control.coverage.record(projectReason) }
        }

        func walk(directory: String, depth: Int, allowArtifacts: Bool) {
            guard !control.shouldStop else { return }
            guard depth <= maxDepth, visitedDirs < maxVisitedDirectories, visitedEntries < maxVisitedEntries else {
                recordCoverage("git_discovery_limit", "project_discovery_limit")
                return
            }
            guard !readPolicy.requiresUnauthedTCCPrompt(directory) else {
                recordCoverage("git_authorization_required", "project_authorization_required")
                return
            }
            guard readPolicy.evaluate(directory, checkSymlinks: true) == .allowed else { return }
            guard let dir = Paths.openDirectory(directory) else {
                recordCoverage("git_directory_unavailable", "project_directory_unavailable")
                return
            }
            visitedDirs += 1

            let collectCurrentArtifacts = collectArtifacts && allowArtifacts
            let isRootPrefix = directory == "/"
            var hasDotGit = false
            var childEntries: [(name: String, dType: Int32)] = []
            var gitOnlySubdirs: [String] = []

            while let entry = readdir(dir) {
                if control.shouldStop { break }
                let name = withUnsafePointer(to: entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                        String(cString: $0)
                    }
                }
                if name == "." || name == ".." { continue }
                guard visitedEntries < maxVisitedEntries else {
                    recordCoverage("git_entry_limit", "project_entry_limit")
                    break
                }
                visitedEntries += 1
                if collectGitRoots && name == ".git" {
                    let gitMarker = isRootPrefix ? "/.git" : "\(directory)/.git"
                    var st = stat()
                    if lstat(gitMarker, &st) == 0 {
                        let mode = st.st_mode & S_IFMT
                        // Both directory (.git/) and regular file (.git gitdir: ...) are valid worktree roots
                        if mode == S_IFDIR || mode == S_IFREG {
                            hasDotGit = true
                        }
                    }
                    continue
                }

                let dType = Int32(entry.pointee.d_type)
                if collectCurrentArtifacts {
                    childEntries.append((name, dType))
                } else if collectGitRoots {
                    if prunedDirectoryNames.contains(name) { continue }
                    // Allow descending into `.worktrees` or `.claude` so nested worktrees are discovered
                    if name.hasPrefix(".") && name != ".worktrees" && name != ".claude" { continue }
                    if dType == DT_DIR || dType == DT_UNKNOWN {
                        let childPath = isRootPrefix ? "/\(name)" : "\(directory)/\(name)"
                        var st = stat()
                        if lstat(childPath, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR {
                            gitOnlySubdirs.append(childPath)
                        }
                    }
                }
            }
            closedir(dir)

            if hasDotGit && seenRepoRoots.insert(directory).inserted {
                result.repoRoots.append(directory)
            }

            if collectCurrentArtifacts {
                let childSet = Set(childEntries.lazy.map(\.name))
                for (name, dType) in childEntries.sorted(by: { $0.name < $1.name }) {
                    if control.shouldStop { break }
                    let fullPath = isRootPrefix ? "/\(name)" : "\(directory)/\(name)"
                    if let matchingRules = rulesByDirName[name],
                       let matched = matchingRules.first(where: { rule in
                           rule.anchorFiles.contains(where: { childSet.contains($0) })
                       }),
                       let anchor = matched.anchorFiles.first(where: { childSet.contains($0) }) {
                        if seenArtifactPaths.insert(fullPath).inserted {
                            let entry = inspectSingleProjectArtifact(
                                artifactPath: fullPath,
                                artifactName: name,
                                projectRoot: directory,
                                anchorFile: anchor,
                                ecosystem: matched.ecosystem,
                                readPolicy: readPolicy,
                                gitExecutable: gitExecutable,
                                checkActiveProcesses: checkActiveProcesses,
                                now: now,
                                control: control,
                                maxEntriesPerArtifact: maxEntriesPerArtifact
                            )
                            result.artifacts.append(entry)
                        }
                        continue
                    }

                    let isGitOnlyDir = collectGitRoots && (name == ".worktrees" || name == ".claude")
                    if prunedDirectoryNames.contains(name) || (name.hasPrefix(".") && !isGitOnlyDir) {
                        continue
                    }
                    if dType == DT_DIR || dType == DT_UNKNOWN {
                        var st = stat()
                        if lstat(fullPath, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR {
                            walk(directory: fullPath, depth: depth + 1, allowArtifacts: !isGitOnlyDir)
                        }
                    }
                }
            } else if collectGitRoots {
                for sub in gitOnlySubdirs.sorted() {
                    if control.shouldStop { break }
                    walk(directory: sub, depth: depth + 1, allowArtifacts: false)
                }
            }
        }

        for rawRoot in authorizedRoots {
            walk(directory: Paths.normalized(rawRoot), depth: 0, allowArtifacts: true)
        }
        return result
    }

    private static func hasGitFileMarker(at path: String) -> Bool {
        var st = stat()
        guard lstat(path + "/.git", &st) == 0 else { return false }
        return (st.st_mode & S_IFMT) == S_IFREG
    }

    private static func runGit(
        gitExecutable: String,
        directory: String,
        args: [String],
        timeout: TimeInterval = 4.0,
        control: ScanControl = ScanControl()
    ) -> CommandResult? {
        let fullArgs = [
            "-c", "core.fsmonitor=false",
            "-c", "core.hooksPath=/dev/null",
            "-C", directory
        ] + args
        return try? CommandRunner.run(gitExecutable, fullArgs, timeout: timeout, control: control)
    }

    private static func detectLocalDefaultBranch(gitExecutable: String, directory: String, control: ScanControl = ScanControl()) -> String? {
        for candidate in ["refs/heads/main", "refs/heads/master", "refs/remotes/origin/main", "refs/remotes/origin/master"] {
            if let res = runGit(gitExecutable: gitExecutable, directory: directory, args: ["show-ref", "--verify", "--quiet", candidate], control: control),
               res.status == 0, !res.timedOut {
                return candidate
            }
        }
        return nil
    }

    private static func countPorcelainStatusZEntries(_ output: String) -> Int {
        // In `git status --porcelain=v1 -z`, each entry starts with XY<space>path\0,
        // and rename/copy entries (`R` or `C` in X or Y) are followed by an extra origPath\0 token.
        let tokens = output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var count = 0
        var skipNext = false
        for token in tokens {
            if skipNext {
                skipNext = false
                continue
            }
            count += 1
            if token.count >= 2 {
                let firstTwo = Array(token.prefix(2))
                if firstTwo[0] == "R" || firstTwo[0] == "C" || firstTwo[1] == "R" || firstTwo[1] == "C" {
                    skipNext = true
                }
            }
        }
        return count
    }

    private static func queryDirectoryProcesses(path: String, control: ScanControl = ScanControl()) -> [Int32]? {
        // Recursively inspect descriptors under this artifact; +d alone cannot establish nested-file inactivity.
        // Failure or the shared deadline leaves usage unknown and the artifact blocked.
        guard let res = try? CommandRunner.run("/usr/sbin/lsof", ["-n", "-P", "-t", "+D", path], timeout: 3.0, control: control) else {
            return nil
        }
        guard !res.timedOut, res.error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              res.status == 0 || (res.status == 1 && res.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) else {
            return nil
        }
        var pids: [Int32] = []
        for line in res.output.split(separator: "\n") {
            if let pid = Int32(line.trimmingCharacters(in: .whitespaces)) {
                pids.append(pid)
            }
        }
        return Array(Set(pids)).sorted()
    }
}
