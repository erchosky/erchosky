import Foundation
import CryptoKit
import Darwin

public enum OrphanBuildStatus: String, Codable, CaseIterable, Sendable {
    case activeProject = "active_project"
    case partial = "partial"
    case cancelled = "cancelled"
    case possiblyOrphaned = "possibly_orphaned"
    case missingMetadata = "missing_metadata"
    case invalidMetadata = "invalid_metadata"
    case permissionDenied = "permission_denied"
    case unknownUnmountedVolume = "unknown_unmounted_volume"
}

public struct OrphanBuildAssessment: Codable, Equatable, Sendable {
    public let buildPath: String
    public let kind: String // "xcode_derived_data" or "xcodebuild_mcp_workspace"
    public let status: OrphanBuildStatus
    public let recordedWorkspacePaths: [String]
    public let missingWorkspacePaths: [String]
    public let existingWorkspacePaths: [String]
    public let unmountedVolumePaths: [String]
    public let recentlyModified: Bool
    public let allocatedBytes: Int64
    public let logicalBytes: Int64
    public let inventoryOnly: Bool
    public let selectionAllowed: Bool
    public let explanationES: String
    public let explanationEN: String

    public init(
        buildPath: String,
        kind: String,
        status: OrphanBuildStatus,
        recordedWorkspacePaths: [String] = [],
        missingWorkspacePaths: [String] = [],
        existingWorkspacePaths: [String] = [],
        unmountedVolumePaths: [String] = [],
        recentlyModified: Bool = false,
        allocatedBytes: Int64 = 0,
        logicalBytes: Int64 = 0,
        explanationES: String,
        explanationEN: String
    ) {
        self.buildPath = buildPath
        self.kind = kind
        self.status = status
        self.recordedWorkspacePaths = recordedWorkspacePaths
        self.missingWorkspacePaths = missingWorkspacePaths
        self.existingWorkspacePaths = existingWorkspacePaths
        self.unmountedVolumePaths = unmountedVolumePaths
        self.recentlyModified = recentlyModified
        self.allocatedBytes = allocatedBytes
        self.logicalBytes = logicalBytes
        self.inventoryOnly = true
        self.selectionAllowed = false
        self.explanationES = explanationES
        self.explanationEN = explanationEN
    }
}

public enum OrphanBuildDetector {
    /// Inspects a single DerivedData project build directory or XcodeBuildMCP/MobileBuildMCP workspace directory.
    /// Uses real PropertyListSerialization and JSONSerialization parsers.
    /// Never classifies permission errors or unmounted external volumes as orphaned.
    public static func inspect(
        buildDirectory rawPath: String,
        readPolicy: ReadAuthorizationPolicy,
        volumesRoot: String = "/Volumes",
        now: Date = Date(),
        premeasuredAllocated: Int64? = nil,
        premeasuredLogical: Int64? = nil,
        control: ScanControl = ScanControl()
    ) -> OrphanBuildAssessment {
        let path = Paths.normalized(rawPath)
        let kind = inferKind(for: path)

        if control.shouldStop {
            return OrphanBuildAssessment(buildPath: path, kind: kind,
                status: control.cancellation.isCancelled ? .cancelled : .partial,
                explanationES: "Inspección interrumpida antes de leer los metadatos.",
                explanationEN: "Inspection interrupted before reading metadata.")
        }
        guard readPolicy.evaluate(path, checkSymlinks: true) == .allowed,
              !readPolicy.requiresUnauthedTCCPrompt(path) else {
            return OrphanBuildAssessment(
                buildPath: path,
                kind: kind,
                status: .permissionDenied,
                explanationES: "Ruta fuera del alcance de lectura autorizado o contiene enlaces simbólicos.",
                explanationEN: "Path is outside authorized read scope or contains symbolic links."
            )
        }

        var dirStat = stat()
        guard lstat(path, &dirStat) == 0 else {
            if errno == EACCES || errno == EPERM {
                return OrphanBuildAssessment(
                    buildPath: path,
                    kind: kind,
                    status: .permissionDenied,
                    explanationES: "Permiso denegado al inspeccionar la carpeta de compilación.",
                    explanationEN: "Permission denied while inspecting build folder."
                )
            }
            return OrphanBuildAssessment(
                buildPath: path,
                kind: kind,
                status: .missingMetadata,
                explanationES: "La carpeta de compilación ya no existe.",
                explanationEN: "Build directory no longer exists."
            )
        }

        guard (dirStat.st_mode & S_IFMT) == S_IFDIR else {
            return OrphanBuildAssessment(
                buildPath: path,
                kind: kind,
                status: .invalidMetadata,
                explanationES: "El elemento no es un directorio de compilación.",
                explanationEN: "Item is not a build directory."
            )
        }

        // Measure directory size safely unless premeasured
        let allocated: Int64
        let logical: Int64
        if let preAlloc = premeasuredAllocated, let preLogic = premeasuredLogical {
            allocated = preAlloc
            logical = preLogic
        } else {
            var seenInodes = Set<InodeKey>()
            var examined = 0
            let measurement = StorageMeasurement.measure(
                path: path,
                category: .developerCaches,
                readPolicy: readPolicy,
                claimedPaths: [],
                neverTouchedPaths: [],
                seenInodes: &seenInodes,
                cancellation: control.cancellation,
                maxEntriesPerItem: 2_000,
                examinedCounter: &examined,
                deadline: control.deadline
            )
            allocated = measurement?.allocatedBytes ?? 0
            logical = measurement?.logicalBytes ?? 0
        }

        let recentlyModified = isRecentlyTouched(path: path, dirStat: dirStat, now: now)

        // Extract workspace references from info.plist / Info.plist and state/daemon/daemon.json
        let extraction = extractWorkspaceReferences(from: path, readPolicy: readPolicy, control: control)
        if control.shouldStop {
            return OrphanBuildAssessment(buildPath: path, kind: kind,
                status: control.cancellation.isCancelled ? .cancelled : .partial,
                recentlyModified: recentlyModified, allocatedBytes: allocated, logicalBytes: logical,
                explanationES: "Inspección interrumpida; no se ha podido comprobar el origen de la compilación.",
                explanationEN: "Inspection interrupted; build origin could not be verified.")
        }
        if extraction.hadPermissionError {
            return OrphanBuildAssessment(
                buildPath: path,
                kind: kind,
                status: .permissionDenied,
                recentlyModified: recentlyModified,
                allocatedBytes: allocated,
                logicalBytes: logical,
                explanationES: "Sin permiso de lectura para los metadatos de compilación (info.plist / daemon.json).",
                explanationEN: "Read permission denied for build metadata (info.plist / daemon.json)."
            )
        }
        if !extraction.foundAnyMetadataFile {
            return OrphanBuildAssessment(
                buildPath: path,
                kind: kind,
                status: .missingMetadata,
                recentlyModified: recentlyModified,
                allocatedBytes: allocated,
                logicalBytes: logical,
                explanationES: "Sin archivo info.plist ni daemon.json; no se puede demostrar qué proyecto originó esta compilación.",
                explanationEN: "No info.plist or daemon.json found; cannot establish which project originated this build."
            )
        }
        if extraction.hadParseError || extraction.workspacePaths.isEmpty {
            return OrphanBuildAssessment(
                buildPath: path,
                kind: kind,
                status: .invalidMetadata,
                recentlyModified: recentlyModified,
                allocatedBytes: allocated,
                logicalBytes: logical,
                explanationES: "Metadatos de compilación incompletos o con formato no válido (sin WorkspacePath/workspaceRoot absoluto).",
                explanationEN: "Incomplete or malformed build metadata (missing absolute WorkspacePath/workspaceRoot)."
            )
        }

        let folderHashSuffix = extract12HexHashSuffix(from: URL(fileURLWithPath: path).lastPathComponent)
        var existingPaths: [String] = []
        var missingPaths: [String] = []
        var unmountedPaths: [String] = []

        for refPath in extraction.workspacePaths {
            let normalizedRef = Paths.normalized(refPath)
            // Check external volume mount status first if under /Volumes/<VolName>/...
            if let unmountedVolume = checkUnmountedVolume(for: normalizedRef, volumesRoot: volumesRoot) {
                unmountedPaths.append("\(normalizedRef) [\(unmountedVolume)]")
                continue
            }

            var refStat = stat()
            if lstat(normalizedRef, &refStat) == 0 {
                existingPaths.append(normalizedRef)
                continue
            }
            let err = errno
            if err == EACCES || err == EPERM {
                return OrphanBuildAssessment(
                    buildPath: path,
                    kind: kind,
                    status: .permissionDenied,
                    recordedWorkspacePaths: extraction.workspacePaths,
                    missingWorkspacePaths: missingPaths,
                    existingWorkspacePaths: existingPaths,
                    unmountedVolumePaths: unmountedPaths,
                    recentlyModified: recentlyModified,
                    allocatedBytes: allocated,
                    logicalBytes: logical,
                    explanationES: "No se pudo comprobar la ruta de origen (\(normalizedRef)) por falta de permisos; no se marca como huérfana.",
                    explanationEN: "Could not verify source path (\(normalizedRef)) due to permission denial; not marked as orphaned."
                )
            }

            // If XcodeBuildMCP hashed workspace suffix matches an existing ancestor directory, treat as active
            if let hash = folderHashSuffix, let matchingAncestor = findExistingAncestorMatchingSHA12(of: normalizedRef, expectedHash: hash) {
                existingPaths.append(matchingAncestor)
                continue
            }

            missingPaths.append(normalizedRef)
        }

        if !unmountedPaths.isEmpty {
            return OrphanBuildAssessment(
                buildPath: path,
                kind: kind,
                status: .unknownUnmountedVolume,
                recordedWorkspacePaths: extraction.workspacePaths,
                missingWorkspacePaths: missingPaths,
                existingWorkspacePaths: existingPaths,
                unmountedVolumePaths: unmountedPaths,
                recentlyModified: recentlyModified,
                allocatedBytes: allocated,
                logicalBytes: logical,
                explanationES: "El proyecto de origen reside en un volumen externo no montado actualmente; estado desconocido (protegido).",
                explanationEN: "Source project resides on an external volume not currently mounted; status unknown (protected)."
            )
        }

        if !existingPaths.isEmpty || recentlyModified {
            let noteES = recentlyModified && existingPaths.isEmpty
                ? "Modificado en los últimos 2 minutos; se considera compilación activa."
                : "Proyecto de origen presente en disco (\(existingPaths.first ?? ""))."
            let noteEN = recentlyModified && existingPaths.isEmpty
                ? "Modified within the last 2 minutes; treated as an active build."
                : "Source project exists on disk (\(existingPaths.first ?? ""))."
            return OrphanBuildAssessment(
                buildPath: path,
                kind: kind,
                status: .activeProject,
                recordedWorkspacePaths: extraction.workspacePaths,
                missingWorkspacePaths: missingPaths,
                existingWorkspacePaths: existingPaths,
                unmountedVolumePaths: [],
                recentlyModified: recentlyModified,
                allocatedBytes: allocated,
                logicalBytes: logical,
                explanationES: noteES,
                explanationEN: noteEN
            )
        }

        return OrphanBuildAssessment(
            buildPath: path,
            kind: kind,
            status: .possiblyOrphaned,
            recordedWorkspacePaths: extraction.workspacePaths,
            missingWorkspacePaths: missingPaths,
            existingWorkspacePaths: [],
            unmountedVolumePaths: [],
            recentlyModified: false,
            allocatedBytes: allocated,
            logicalBytes: logical,
            explanationES: "Posible compilación huérfana (solo inventario): la ruta de origen registrada (\(missingPaths.joined(separator: ", "))) ya no existe en este Mac.",
            explanationEN: "Possibly orphaned build (inventory only): recorded source path (\(missingPaths.joined(separator: ", "))) no longer exists on this Mac."
        )
    }

    /// Scans all known DerivedData and XcodeBuildMCP / MobileBuildMCP workspace directories under `home`.
    public static func scanAll(
        home rawHome: String = NSHomeDirectory(),
        readPolicy: ReadAuthorizationPolicy? = nil,
        volumesRoot: String = "/Volumes",
        now: Date = Date(),
        maxVisitedEntries: Int = 10_000,
        control: ScanControl = ScanControl()
    ) -> [OrphanBuildAssessment] {
        let home = Paths.normalized(rawHome)
        let policy = readPolicy ?? ReadAuthorizationPolicy(home: home, allowSystemLocations: false)
        let baseDirs = [
            home + "/Library/Developer/Xcode/DerivedData",
            home + "/Library/Developer/XcodeBuildMCP/workspaces",
            home + "/Library/Developer/MobileBuildMCP/workspaces"
        ]
        var results: [OrphanBuildAssessment] = []
        var visitedEntries = 0
        for base in baseDirs {
            if control.shouldStop { break }
            guard policy.evaluate(base) == .allowed, !policy.requiresUnauthedTCCPrompt(base) else { continue }
            guard let dir = Paths.openDirectory(base) else {
                if errno != ENOENT { control.coverage.record("build_directory_unavailable") }
                continue
            }
            defer { closedir(dir) }
            var children: [String] = []
            while let entry = readdir(dir) {
                if control.shouldStop { break }
                let name = withUnsafePointer(to: entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                        String(cString: $0)
                    }
                }
                if name == "." || name == ".." { continue }
                guard visitedEntries < maxVisitedEntries else { control.coverage.record("build_entry_limit"); break }
                visitedEntries += 1
                if name.hasPrefix(".") || name == "ModuleCache.noindex" || name == "SymbolCache.noindex" {
                    continue
                }
                let full = base + "/" + name
                var st = stat()
                if lstat(full, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR {
                    children.append(full)
                }
            }
            children.sort()
            for child in children {
                if control.shouldStop { break }
                results.append(inspect(buildDirectory: child, readPolicy: policy, volumesRoot: volumesRoot, now: now, control: control))
            }
        }
        return results
    }

    private struct MetadataExtraction {
        var foundAnyMetadataFile = false
        var hadParseError = false
        var hadPermissionError = false
        var workspacePaths: [String] = []
    }

    private static func extractWorkspaceReferences(from buildDir: String, readPolicy: ReadAuthorizationPolicy, control: ScanControl) -> MetadataExtraction {
        var result = MetadataExtraction()
        var orderedPaths: [String] = []

        // 1. Direct info.plist / Info.plist and DerivedData/info.plist
        var plistCandidates = [
            buildDir + "/info.plist",
            buildDir + "/Info.plist",
            buildDir + "/DerivedData/info.plist",
            buildDir + "/DerivedData/Info.plist"
        ]

        // Also check DerivedData/*/info.plist inside XcodeBuildMCP workspaces
        let nestedDerivedData = buildDir + "/DerivedData"
        if readPolicy.evaluate(nestedDerivedData) == .allowed, let dir = Paths.openDirectory(nestedDerivedData) {
            defer { closedir(dir) }
            while let entry = readdir(dir) {
                if control.shouldStop { break }
                let name = withUnsafePointer(to: entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                        String(cString: $0)
                    }
                }
                if name == "." || name == ".." || name.hasPrefix(".") { continue }
                plistCandidates.append("\(nestedDerivedData)/\(name)/info.plist")
                plistCandidates.append("\(nestedDerivedData)/\(name)/Info.plist")
            }
        }

        var visitedFiles = Set<String>()
        for plistPath in plistCandidates {
            if control.shouldStop { break }
            if readPolicy.evaluate(plistPath) != .allowed { continue }
            var st = stat()
            if lstat(plistPath, &st) != 0 {
                if errno == EACCES || errno == EPERM {
                    result.hadPermissionError = true
                }
                continue
            }
            guard (st.st_mode & S_IFMT) == S_IFREG else { continue }
            let inoKey = "\(st.st_dev):\(st.st_ino)"
            guard visitedFiles.insert(inoKey).inserted else { continue }

            result.foundAnyMetadataFile = true
            guard let data = readBoundedFile(path: plistPath, maxBytes: 512 * 1024, hadPermissionError: &result.hadPermissionError) else {
                result.hadParseError = true
                continue
            }
            do {
                let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                guard let dict = plist as? [String: Any],
                      let rawWorkspace = dict["WorkspacePath"] as? String else {
                    result.hadParseError = true
                    continue
                }
                let trimmed = rawWorkspace.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("/"), !trimmed.contains("\0") else {
                    result.hadParseError = true
                    continue
                }
                if !orderedPaths.contains(trimmed) {
                    orderedPaths.append(trimmed)
                }
            } catch {
                result.hadParseError = true
            }
        }

        // 2. XcodeBuildMCP / MobileBuildMCP state/daemon/daemon.json
        let daemonJSONPath = buildDir + "/state/daemon/daemon.json"
        if control.shouldStop { return result }
        guard readPolicy.evaluate(daemonJSONPath) == .allowed else {
            result.workspacePaths = orderedPaths
            return result
        }
        var daemonStat = stat()
        if lstat(daemonJSONPath, &daemonStat) == 0 {
            if (daemonStat.st_mode & S_IFMT) == S_IFREG {
                result.foundAnyMetadataFile = true
                if let data = readBoundedFile(path: daemonJSONPath, maxBytes: 512 * 1024, hadPermissionError: &result.hadPermissionError) {
                    do {
                        let obj = try JSONSerialization.jsonObject(with: data, options: [])
                        if let dict = obj as? [String: Any],
                           let rawRoot = dict["workspaceRoot"] as? String {
                            let trimmed = rawRoot.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed.hasPrefix("/"), !trimmed.contains("\0") {
                                if !orderedPaths.contains(trimmed) {
                                    orderedPaths.append(trimmed)
                                }
                            } else {
                                result.hadParseError = true
                            }
                        } else {
                            result.hadParseError = true
                        }
                    } catch {
                        result.hadParseError = true
                    }
                } else {
                    result.hadParseError = true
                }
            }
        } else if errno == EACCES || errno == EPERM {
            result.hadPermissionError = true
        }

        result.workspacePaths = orderedPaths
        return result
    }

    private static func readBoundedFile(path: String, maxBytes: Int, hadPermissionError: inout Bool) -> Data? {
        guard !ReadAuthorizationPolicy.hasSymlinkComponent(path) else { return nil }
        let fd = Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else {
            if errno == EACCES || errno == EPERM {
                hadPermissionError = true
            }
            return nil
        }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_size >= 0, st.st_size <= maxBytes else {
            return nil
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        guard let data = try? handle.read(upToCount: maxBytes + 1), data.count <= maxBytes else { return nil }
        return data
    }

    private static func checkUnmountedVolume(for path: String, volumesRoot: String) -> String? {
        let normVolumes = Paths.normalized(volumesRoot)
        let prefix = normVolumes == "/" ? "/Volumes/" : normVolumes + "/"
        let effectivePrefix: String
        let effectiveVolumesRoot: String
        if path.hasPrefix(prefix) {
            effectivePrefix = prefix
            effectiveVolumesRoot = normVolumes
        } else if path.hasPrefix("/Volumes/") {
            effectivePrefix = "/Volumes/"
            effectiveVolumesRoot = "/Volumes"
        } else {
            return nil
        }

        let remainder = String(path.dropFirst(effectivePrefix.count))
        guard let volumeName = remainder.split(separator: "/").first, !volumeName.isEmpty else {
            return nil
        }
        let mountPoint = "\(effectiveVolumesRoot)/\(volumeName)"
        var st = stat()
        guard lstat(mountPoint, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else {
            return String(volumeName)
        }
        return nil
    }

    private static func isRecentlyTouched(path: String, dirStat: stat, now: Date) -> Bool {
        let rootMod = Double(dirStat.st_mtimespec.tv_sec) + Double(dirStat.st_mtimespec.tv_nsec) / 1e9
        if now.timeIntervalSince1970 - rootMod < 120 {
            return true
        }
        guard let dir = Paths.openDirectory(path) else { return false }
        defer { closedir(dir) }
        while let entry = readdir(dir) {
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }
            let child = "\(path)/\(name)"
            var st = stat()
            if lstat(child, &st) == 0 {
                let mod = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9
                if now.timeIntervalSince1970 - mod < 120 {
                    return true
                }
            }
        }
        return false
    }

    public static func sha12(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    private static func extract12HexHashSuffix(from folderName: String) -> String? {
        guard let dashIdx = folderName.lastIndex(of: "-") else { return nil }
        let suffix = String(folderName[folderName.index(after: dashIdx)...]).lowercased()
        guard suffix.count == 12, suffix.allSatisfy({ ("0"..."9").contains($0) || ("a"..."f").contains($0) }) else {
            return nil
        }
        return suffix
    }

    private static func findExistingAncestorMatchingSHA12(of path: String, expectedHash: String) -> String? {
        var current = path
        while current != "/" && !current.isEmpty {
            current = URL(fileURLWithPath: current).deletingLastPathComponent().path
            if current == "/" || current.isEmpty { break }
            if sha12(current) == expectedHash {
                var st = stat()
                if lstat(current, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR {
                    return current
                }
            }
        }
        return nil
    }

    private static func inferKind(for path: String) -> String {
        let lower = path.lowercased()
        if lower.contains("xcodebuildmcp") || lower.contains("mobilebuildmcp") {
            return "xcodebuild_mcp_workspace"
        }
        return "xcode_derived_data"
    }
}
