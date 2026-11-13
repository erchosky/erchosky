import Foundation
import Darwin
import CryptoKit

/// Stage of progressive duplicate discovery.
public enum DuplicateScanStage: String, Codable, Equatable, Sendable {
    case collectingSizes = "collecting_sizes"
    case preliminaryCompare = "preliminary_compare"
    case hashingSHA256 = "hashing_sha256"
    case completed = "completed"
    case cancelled = "cancelled"
}

/// Live progress snapshot emitted during duplicate scanning.
public struct DuplicateScanProgress: Equatable, Sendable {
    public let stage: DuplicateScanStage
    public let visitedFiles: Int
    public let sizeCandidateGroups: Int
    public let hashedFiles: Int
    public let totalCandidateFiles: Int
    public let hashedBytes: Int64
    public let totalCandidateBytes: Int64
}

/// Work limits bounding duplicate scans over arbitrary user-authorized folders.
public struct DuplicateScanConfiguration: Equatable, Sendable {
    public let minimumFileSizeBytes: Int64
    public let maxDepth: Int
    public let maxVisitedFiles: Int
    public let maxBytesToHash: Int64
    public let preliminarySampleBytes: Int

    public init(
        minimumFileSizeBytes: Int64 = 1,
        maxDepth: Int = 12,
        maxVisitedFiles: Int = 50_000,
        maxBytesToHash: Int64 = 8_589_934_592, // 8 GiB hashing ceiling per run
        preliminarySampleBytes: Int = 16_384
    ) {
        self.minimumFileSizeBytes = max(1, minimumFileSizeBytes)
        self.maxDepth = max(1, maxDepth)
        self.maxVisitedFiles = max(10, maxVisitedFiles)
        self.maxBytesToHash = max(1024, maxBytesToHash)
        self.preliminarySampleBytes = max(4096, preliminarySampleBytes)
    }
}

/// Dedicated read-content authorization policy for user-selected folders, separate from metadata-only inventory.
public struct DuplicateScopePolicy: Sendable {
    public static let blockedSystemPrefixes: [String] = [
        "/System", "/Library", "/usr", "/bin", "/sbin",
        "/private/etc", "/private/var/db", "/private/var/root", "/private/var/log", "/private/var/vm", "/private/var/run",
        "/dev", "/Volumes/.timemachine"
    ]

    public let home: String
    public let authorizedFolders: [String]
    public let protectedPaths: [String]

    public init(
        home: String = NSHomeDirectory(),
        authorizedFolders: [String],
        protectedPaths: [String] = []
    ) {
        self.home = Paths.normalized(home)
        self.authorizedFolders = authorizedFolders.map(Paths.normalized)
        self.protectedPaths = protectedPaths.map(Paths.normalized)
    }

    public func validateFolder(_ rawPath: String) -> (allowed: Bool, reasonES: String?, reasonEN: String?) {
        let path = Paths.normalized(rawPath)
        guard !path.isEmpty, path != "/", path != home else {
            return (
                false,
                "Elige subcarpetas concretas autorizadas (no toda la raíz ni toda la carpeta personal).",
                "Choose specific authorized subfolders rather than / or your entire home folder."
            )
        }
        if path == "/private" || path == "/private/var" || Self.blockedSystemPrefixes.contains(where: { SafetyPolicy.within(path, $0) }) {
            return (
                false,
                "Las ubicaciones del sistema están excluidas del buscador de duplicados.",
                "System locations are excluded from duplicate content scanning."
            )
        }
        let forbiddenSensitive = ReadAuthorizationPolicy.forbiddenHomeRelativePrefixes.map {
            Paths.normalized(home + "/" + $0)
        } + [Paths.normalized(home + "/.Trash"), Paths.normalized(home + "/Library/Keychains")]
        if forbiddenSensitive.contains(where: { SafetyPolicy.within(path, $0) || SafetyPolicy.within($0, path) && path == home }) {
            return (
                false,
                "Carpeta sensible protegida (credenciales, llaveros o datos privados).",
                "Protected sensitive folder (credentials, keychains, or private data)."
            )
        }
        if Paths.containsAncestor(of: path, in: Set(protectedPaths)) {
            return (
                false,
                "Esta carpeta o una superior está protegida por el usuario.",
                "This folder or an ancestor is protected by the user."
            )
        }
        do {
            try SafetyPolicy.rejectSymlinks(path)
        } catch {
            let msg = error.localizedDescription
            if msg.contains("World-writable") {
                return (
                    false,
                    "No se escanean carpetas dentro de ubicaciones compartidas con escritura pública (como /tmp).",
                    "Folders inside shared world-writable locations (such as /tmp) are excluded."
                )
            } else if msg.contains("Untrusted") {
                return (
                    false,
                    "La ruta contiene un directorio con propietario no confiable.",
                    "The path contains a directory with an untrusted owner."
                )
            } else {
                return (
                    false,
                    "No se escanean carpetas con enlaces simbólicos en la ruta.",
                    "Folders containing symbolic links in their path are excluded."
                )
            }
        }
        var st = stat()
        guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else {
            return (
                false,
                "La carpeta autorizada no existe o no es un directorio accesible.",
                "Authorized folder does not exist or is not an accessible directory."
            )
        }
        return (true, nil, nil)
    }

    public func isPathProtectedOrSensitive(_ rawPath: String) -> Bool {
        let path = Paths.normalized(rawPath)
        guard authorizedFolders.contains(where: { SafetyPolicy.within(path, $0) }) else {
            return true
        }
        if Paths.containsAncestor(of: path, in: Set(protectedPaths)) {
            return true
        }
        let sensitive = ReadAuthorizationPolicy.forbiddenHomeRelativePrefixes.map {
            Paths.normalized(home + "/" + $0)
        } + [Paths.normalized(home + "/.Trash")]
        return sensitive.contains { SafetyPolicy.within(path, $0) }
    }
}

/// One physical file copy participating in a verified SHA-256 duplicate group.
public struct DuplicateFileEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let fileName: String
    public let parentDirectory: String
    public let logicalBytes: Int64
    public let allocatedBytes: Int64
    public let modifiedAt: Date
    public let identity: FileIdentity
    public let sha256: String
    public let physicalExtentOffset: Int64?
    public let volumeIsAPFS: Bool

    public init(
        path: String,
        fileName: String? = nil,
        parentDirectory: String? = nil,
        logicalBytes: Int64,
        allocatedBytes: Int64,
        modifiedAt: Date,
        identity: FileIdentity,
        sha256: String,
        physicalExtentOffset: Int64? = nil,
        volumeIsAPFS: Bool = false
    ) {
        self.path = Paths.normalized(path)
        let url = URL(fileURLWithPath: self.path)
        self.fileName = fileName ?? url.lastPathComponent
        self.parentDirectory = parentDirectory ?? url.deletingLastPathComponent().path
        self.logicalBytes = logicalBytes
        self.allocatedBytes = allocatedBytes
        self.modifiedAt = modifiedAt
        self.identity = identity
        self.sha256 = sha256
        self.physicalExtentOffset = physicalExtentOffset
        self.volumeIsAPFS = volumeIsAPFS
    }
}

/// Exact content duplicate group guaranteed to have >= 2 independent inodes with identical SHA-256.
public struct DuplicateGroup: Codable, Equatable, Sendable, Identifiable {
    public var id: String { sha256 + "-\(logicalBytes)" }
    public let sha256: String
    public let logicalBytes: Int64
    public let files: [DuplicateFileEntry]
    public let suggestedProtectedPath: String
    public let likelyContainsAPFSClones: Bool

    public var surplusCount: Int { max(0, files.count - 1) }

    public var potentialSelectedBytes: Int64 {
        files.filter { $0.path != suggestedProtectedPath }.reduce(0) { ByteTotals.adding($0, $1.allocatedBytes) }
    }

    /// Conservative estimate of physically reclaimable space when removing all surplus copies except the protected one.
    public func estimatedReclaimableBytes(deletingPaths: Set<String>, protectedPath: String) -> Int64 {
        let targets = files.filter { deletingPaths.contains($0.path) && $0.path != protectedPath }
        guard !targets.isEmpty else { return 0 }
        let kept = files.first { $0.path == protectedPath }
        var total: Int64 = 0
        for file in targets {
            // If APFS clone detection observed identical non-zero physical start block as kept copy,
            // trashing this clone will release 0 data blocks while kept copy still retains those extents.
            if let keptOffset = kept?.physicalExtentOffset,
               let fileOffset = file.physicalExtentOffset,
               keptOffset > 0, keptOffset == fileOffset {
                continue
            }
            total = ByteTotals.adding(total, file.allocatedBytes)
        }
        return total
    }
}

/// Complete telemetry + verified duplicate groups returned by `ExactDuplicateScanner`.
public struct DuplicateScanReport: Equatable, Sendable {
    public let groups: [DuplicateGroup]
    public let scannedFolders: [String]
    public let rejectedFolders: [(path: String, reasonES: String, reasonEN: String)]
    public let visitedFilesCount: Int
    public let skippedSymlinksCount: Int
    public let skippedHardlinksCount: Int
    public let skippedCloudOnlyCount: Int
    public let skippedPackagesCount: Int
    public let skippedProtectedCount: Int
    public let truncatedAtWorkLimit: Bool
    public let cancelled: Bool

    public static func == (lhs: DuplicateScanReport, rhs: DuplicateScanReport) -> Bool {
        lhs.groups == rhs.groups
            && lhs.scannedFolders == rhs.scannedFolders
            && lhs.visitedFilesCount == rhs.visitedFilesCount
            && lhs.skippedSymlinksCount == rhs.skippedSymlinksCount
            && lhs.skippedHardlinksCount == rhs.skippedHardlinksCount
            && lhs.skippedCloudOnlyCount == rhs.skippedCloudOnlyCount
            && lhs.skippedPackagesCount == rhs.skippedPackagesCount
            && lhs.truncatedAtWorkLimit == rhs.truncatedAtWorkLimit
            && lhs.cancelled == rhs.cancelled
    }
}

/// Progressive exact duplicate finder: size -> preliminary sample -> streaming SHA-256.
public enum ExactDuplicateScanner {
    private static let packageBundleExtensions: Set<String> = [
        "app", "bundle", "framework", "kext", "plugin", "xpc", "appex",
        "xcodeproj", "xcworkspace", "playground", "photoslibrary", "fcpbundle", "rtfd"
    ]

    // macOS SF_DATALESS flag (0x40000000) indicates cloud/dataless placeholder not materialized locally.
    private static let datalessFlag: UInt32 = 0x4000_0000

    public static func scan(
        scope: DuplicateScopePolicy,
        configuration: DuplicateScanConfiguration = DuplicateScanConfiguration(),
        control: ScanControl = ScanControl(),
        onProgress: (@Sendable (DuplicateScanProgress) -> Void)? = nil
    ) -> DuplicateScanReport {
        var validFolders: [String] = []
        var rejectedFolders: [(path: String, reasonES: String, reasonEN: String)] = []
        var seenFolders = Set<String>()

        for raw in scope.authorizedFolders {
            let norm = Paths.normalized(raw)
            guard seenFolders.insert(norm).inserted else { continue }
            let decision = scope.validateFolder(norm)
            if decision.allowed {
                validFolders.append(norm)
            } else {
                rejectedFolders.append((norm, decision.reasonES ?? "Bloqueado", decision.reasonEN ?? "Blocked"))
            }
        }

        // Remove redundant nested subfolders when an ancestor folder is already included.
        let minimalRoots = validFolders.sorted { $0.count < $1.count }.reduce(into: [String]()) { acc, path in
            if !acc.contains(where: { SafetyPolicy.within(path, $0) }) {
                acc.append(path)
            }
        }

        struct CandidateFile {
            let path: String
            let size: Int64
            let allocatedBytes: Int64
            let modifiedAt: Date
            let identity: FileIdentity
            let volumeIsAPFS: Bool
            let physicalOffset: Int64?
        }

        var seenInodes = Set<InodeKey>()
        var sizeBuckets: [Int64: [CandidateFile]] = [:]
        var visitedFiles = 0
        var skippedSymlinks = 0
        var skippedHardlinks = 0
        var skippedCloud = 0
        var skippedPackages = 0
        var skippedProtected = 0
        var truncated = false
        var fsAPFSCache: [UInt64: Bool] = [:]

        func walk(directory: String, depth: Int) {
            if control.shouldStop || truncated { return }
            guard depth <= configuration.maxDepth else { return }
            guard !scope.isPathProtectedOrSensitive(directory) else {
                skippedProtected += 1
                return
            }
            guard let dir = Paths.openDirectory(directory) else { return }
            defer { closedir(dir) }

            let isRoot = directory == "/"
            var subdirs: [String] = []

            while let entry = readdir(dir) {
                if control.shouldStop || truncated { break }
                let name = withUnsafePointer(to: entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                        String(cString: $0)
                    }
                }
                if name == "." || name == ".." { continue }
                if name == ".git" || name == ".Trash" {
                    skippedProtected += 1
                    continue
                }
                let childPath = isRoot ? "/\(name)" : "\(directory)/\(name)"
                if scope.isPathProtectedOrSensitive(childPath) {
                    skippedProtected += 1
                    continue
                }

                var st = stat()
                guard lstat(childPath, &st) == 0 else { continue }
                let mode = st.st_mode & S_IFMT

                if mode == S_IFLNK {
                    skippedSymlinks += 1
                    continue
                }

                let ext = URL(fileURLWithPath: childPath).pathExtension.lowercased()
                if mode == S_IFDIR {
                    if packageBundleExtensions.contains(ext) {
                        skippedPackages += 1
                        continue
                    }
                    let rv = try? URL(fileURLWithPath: childPath).resourceValues(forKeys: [.isPackageKey])
                    if rv?.isPackage == true {
                        skippedPackages += 1
                        continue
                    }
                    subdirs.append(childPath)
                    continue
                }

                guard mode == S_IFREG else { continue }
                visitedFiles += 1
                if visitedFiles > configuration.maxVisitedFiles {
                    truncated = true
                    break
                }

                if (st.st_flags & datalessFlag) != 0 || isCloudOnlyUbiquitous(path: childPath) {
                    skippedCloud += 1
                    continue
                }

                let dev = UInt64(UInt32(bitPattern: st.st_dev))
                let inoKey = InodeKey(device: dev, inode: st.st_ino)
                guard seenInodes.insert(inoKey).inserted else {
                    skippedHardlinks += 1
                    continue
                }

                let size = Int64(st.st_size)
                guard size >= configuration.minimumFileSizeBytes else { continue }

                let isAPFS: Bool
                if let cached = fsAPFSCache[dev] {
                    isAPFS = cached
                } else {
                    isAPFS = checkVolumeIsAPFS(path: childPath)
                    fsAPFSCache[dev] = isAPFS
                }

                let allocated = Int64(st.st_blocks) * 512
                let mod = Date(timeIntervalSince1970: Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9)
                let cand = CandidateFile(
                    path: childPath,
                    size: size,
                    allocatedBytes: allocated,
                    modifiedAt: mod,
                    identity: SafetyPolicy.identity(st),
                    volumeIsAPFS: isAPFS,
                    physicalOffset: isAPFS ? queryPhysicalExtentOffset(path: childPath) : nil
                )
                sizeBuckets[size, default: []].append(cand)

                if visitedFiles % 250 == 0 {
                    onProgress?(DuplicateScanProgress(
                        stage: .collectingSizes,
                        visitedFiles: visitedFiles,
                        sizeCandidateGroups: sizeBuckets.values.filter { $0.count > 1 }.count,
                        hashedFiles: 0,
                        totalCandidateFiles: 0,
                        hashedBytes: 0,
                        totalCandidateBytes: 0
                    ))
                }
            }

            for sub in subdirs.sorted() {
                if control.shouldStop || truncated { break }
                walk(directory: sub, depth: depth + 1)
            }
        }

        for root in minimalRoots {
            walk(directory: root, depth: 0)
        }

        if control.shouldStop {
            return DuplicateScanReport(
                groups: [],
                scannedFolders: minimalRoots,
                rejectedFolders: rejectedFolders,
                visitedFilesCount: visitedFiles,
                skippedSymlinksCount: skippedSymlinks,
                skippedHardlinksCount: skippedHardlinks,
                skippedCloudOnlyCount: skippedCloud,
                skippedPackagesCount: skippedPackages,
                skippedProtectedCount: skippedProtected,
                truncatedAtWorkLimit: truncated,
                cancelled: true
            )
        }

        // Stage 2: Preliminary boundary-chunk comparison for larger files (> 64 KiB)
        let sameSizeGroups = sizeBuckets.filter { $0.value.count >= 2 }
        var hashCandidates: [CandidateFile] = []
        let preliminaryThreshold = Int64(configuration.preliminarySampleBytes * 3)

        onProgress?(DuplicateScanProgress(
            stage: .preliminaryCompare,
            visitedFiles: visitedFiles,
            sizeCandidateGroups: sameSizeGroups.count,
            hashedFiles: 0,
            totalCandidateFiles: sameSizeGroups.values.reduce(0) { $0 + $1.count },
            hashedBytes: 0,
            totalCandidateBytes: sameSizeGroups.reduce(0) { $0 + ($1.key * Int64($1.value.count)) }
        ))

        for (size, candidates) in sameSizeGroups.sorted(by: { $0.key > $1.key }) {
            if control.shouldStop { break }
            if size <= preliminaryThreshold {
                hashCandidates.append(contentsOf: candidates)
                continue
            }
            var partialBuckets: [Data: [CandidateFile]] = [:]
            for cand in candidates {
                if control.shouldStop { break }
                if let sample = preliminaryDigest(
                    path: cand.path,
                    expectedIdentity: cand.identity,
                    sampleBytes: configuration.preliminarySampleBytes
                ) {
                    partialBuckets[sample, default: []].append(cand)
                }
            }
            for (_, group) in partialBuckets where group.count >= 2 {
                hashCandidates.append(contentsOf: group)
            }
        }

        // Stage 3: Streaming SHA-256 verification without buffering whole files in RAM
        let totalCandidateFiles = hashCandidates.count
        let totalCandidateBytes = hashCandidates.reduce(Int64(0)) { ByteTotals.adding($0, $1.size) }
        var hashedBytes: Int64 = 0
        var hashedFiles = 0

        struct ExactBucketKey: Hashable {
            let size: Int64
            let sha256: String
        }
        var verifiedBuckets: [ExactBucketKey: [DuplicateFileEntry]] = [:]

        for cand in hashCandidates {
            if control.shouldStop { break }
            if ByteTotals.adding(hashedBytes, cand.size) > configuration.maxBytesToHash && hashedBytes > 0 {
                truncated = true
                break
            }
            guard let digest = streamingSHA256(
                path: cand.path,
                expectedIdentity: cand.identity,
                control: control
            ) else {
                continue
            }
            hashedFiles += 1
            hashedBytes = ByteTotals.adding(hashedBytes, cand.size)

            let entry = DuplicateFileEntry(
                path: cand.path,
                logicalBytes: cand.size,
                allocatedBytes: cand.allocatedBytes,
                modifiedAt: cand.modifiedAt,
                identity: cand.identity,
                sha256: digest,
                physicalExtentOffset: cand.physicalOffset,
                volumeIsAPFS: cand.volumeIsAPFS
            )
            verifiedBuckets[ExactBucketKey(size: cand.size, sha256: digest), default: []].append(entry)

            if hashedFiles % 20 == 0 || hashedFiles == totalCandidateFiles {
                onProgress?(DuplicateScanProgress(
                    stage: .hashingSHA256,
                    visitedFiles: visitedFiles,
                    sizeCandidateGroups: sameSizeGroups.count,
                    hashedFiles: hashedFiles,
                    totalCandidateFiles: totalCandidateFiles,
                    hashedBytes: hashedBytes,
                    totalCandidateBytes: totalCandidateBytes
                ))
            }
        }

        if control.shouldStop {
            return DuplicateScanReport(
                groups: [],
                scannedFolders: minimalRoots,
                rejectedFolders: rejectedFolders,
                visitedFilesCount: visitedFiles,
                skippedSymlinksCount: skippedSymlinks,
                skippedHardlinksCount: skippedHardlinks,
                skippedCloudOnlyCount: skippedCloud,
                skippedPackagesCount: skippedPackages,
                skippedProtectedCount: skippedProtected,
                truncatedAtWorkLimit: truncated,
                cancelled: true
            )
        }

        let groups: [DuplicateGroup] = verifiedBuckets.compactMap { key, entries in
            guard entries.count >= 2 else { return nil }
            let sorted = entries.sorted { lhs, rhs in
                if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt < rhs.modifiedAt }
                return lhs.path < rhs.path
            }
            let suggestedKeep = sorted.first?.path ?? entries[0].path
            let nonZeroOffsets = entries.compactMap(\.physicalExtentOffset).filter { $0 > 0 }
            let sharedAPFSExtent = Set(nonZeroOffsets).count < nonZeroOffsets.count && nonZeroOffsets.count >= 2
            return DuplicateGroup(
                sha256: key.sha256,
                logicalBytes: key.size,
                files: sorted,
                suggestedProtectedPath: suggestedKeep,
                likelyContainsAPFSClones: sharedAPFSExtent
            )
        }
        .sorted { lhs, rhs in
            if lhs.potentialSelectedBytes != rhs.potentialSelectedBytes {
                return lhs.potentialSelectedBytes > rhs.potentialSelectedBytes
            }
            return lhs.logicalBytes > rhs.logicalBytes
        }

        onProgress?(DuplicateScanProgress(
            stage: .completed,
            visitedFiles: visitedFiles,
            sizeCandidateGroups: groups.count,
            hashedFiles: hashedFiles,
            totalCandidateFiles: totalCandidateFiles,
            hashedBytes: hashedBytes,
            totalCandidateBytes: totalCandidateBytes
        ))

        return DuplicateScanReport(
            groups: groups,
            scannedFolders: minimalRoots,
            rejectedFolders: rejectedFolders,
            visitedFilesCount: visitedFiles,
            skippedSymlinksCount: skippedSymlinks,
            skippedHardlinksCount: skippedHardlinks,
            skippedCloudOnlyCount: skippedCloud,
            skippedPackagesCount: skippedPackages,
            skippedProtectedCount: skippedProtected,
            truncatedAtWorkLimit: truncated,
            cancelled: false
        )
    }

    public static func streamingSHA256(
        path: String,
        expectedIdentity: FileIdentity?,
        control: ScanControl = ScanControl()
    ) -> String? {
        let fd = Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return nil }
        if (st.st_flags & datalessFlag) != 0 { return nil }
        if let expectedIdentity, SafetyPolicy.identity(st) != expectedIdentity {
            return nil
        }

        var hasher = SHA256()
        let chunkSize = 65_536
        var buffer = [UInt8](repeating: 0, count: chunkSize)

        while true {
            if control.shouldStop { return nil }
            let bytesRead = buffer.withUnsafeMutableBytes { ptr in
                Darwin.read(fd, ptr.baseAddress, chunkSize)
            }
            if bytesRead < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if bytesRead == 0 { break }
            hasher.update(data: buffer[0..<bytesRead])
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func preliminaryDigest(
        path: String,
        expectedIdentity: FileIdentity,
        sampleBytes: Int
    ) -> Data? {
        let fd = Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var st = stat()
        guard fstat(fd, &st) == 0,
              (st.st_mode & S_IFMT) == S_IFREG,
              SafetyPolicy.identity(st) == expectedIdentity else {
            return nil
        }

        let size = Int64(st.st_size)
        var hasher = SHA256()
        var len = size
        hasher.update(data: Data(bytes: &len, count: MemoryLayout<Int64>.size))

        var buffer = [UInt8](repeating: 0, count: sampleBytes)
        let offsets: [off_t] = [
            0,
            off_t(max(0, (size / 2) - Int64(sampleBytes / 2))),
            off_t(max(0, size - Int64(sampleBytes)))
        ]

        for offset in offsets {
            let count = buffer.withUnsafeMutableBytes { ptr in
                Darwin.pread(fd, ptr.baseAddress, sampleBytes, offset)
            }
            guard count >= 0 else { return nil }
            if count > 0 {
                hasher.update(data: buffer[0..<count])
            }
        }
        return Data(hasher.finalize())
    }

    private static func isCloudOnlyUbiquitous(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
              values.isUbiquitousItem == true else {
            return false
        }
        if let status = values.ubiquitousItemDownloadingStatus, status == .notDownloaded {
            return true
        }
        return false
    }

    private static func checkVolumeIsAPFS(path: String) -> Bool {
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { return false }
        let name = withUnsafeBytes(of: fs.f_fstypename) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return name.lowercased() == "apfs"
    }

    private static func queryPhysicalExtentOffset(path: String) -> Int64? {
        let fd = Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = log2phys(l2p_flags: 0, l2p_contigbytes: 0, l2p_devoffset: 0)
        guard fcntl(fd, F_LOG2PHYS, &info) == 0 else { return nil }
        return Int64(info.l2p_devoffset)
    }
}

/// Reviewable selection pairing one kept copy with explicit surplus copies for deletion.
public struct DuplicateGroupSelection: Equatable, Sendable {
    public let group: DuplicateGroup
    public let protectedFilePath: String
    public let surplusFilePaths: [String]

    public init(group: DuplicateGroup, protectedFilePath: String, surplusFilePaths: [String]) {
        self.group = group
        self.protectedFilePath = Paths.normalized(protectedFilePath)
        self.surplusFilePaths = surplusFilePaths.map(Paths.normalized)
    }
}

/// Validates and executes Trash cleanup for duplicate surplus copies while protecting >= 1 verified copy per group.
public final class DuplicateCleaner: @unchecked Sendable {
    private let journal: Journal
    private let mover: TrashMoving
    private let scope: DuplicateScopePolicy
    private let home: String
    private let lock = NSLock()

    public init(
        journal: Journal,
        scope: DuplicateScopePolicy,
        home: String = NSHomeDirectory(),
        mover: TrashMoving = SystemTrashMover()
    ) {
        self.journal = journal
        self.scope = scope
        self.home = Paths.normalized(home)
        self.mover = mover
    }

    public func buildPlan(selections: [DuplicateGroupSelection]) -> OperationPlan {
        var resources: [OperationAffectedResource] = []
        var blockers: [OperationBlocker] = []
        var selectedBytes: Int64 = 0
        var estimatedReclaimed: Int64 = 0
        var totalLogical: Int64 = 0
        var anyAPFS = false
        var anyCloneDetected = false
        var protectedSamples: [String] = []

        for sel in selections {
            let cleanTargets = sel.surplusFilePaths.filter { $0 != sel.protectedFilePath }
            if cleanTargets.isEmpty { continue }

            guard let kept = sel.group.files.first(where: { $0.path == sel.protectedFilePath }) else {
                blockers.append(OperationBlocker(
                    reasonES: "Cada grupo debe conservar una copia protegida válida.",
                    reasonEN: "Each group must designate a valid protected kept copy."
                ))
                continue
            }

            let targetSet = Set(cleanTargets)
            if targetSet.count >= sel.group.files.count {
                blockers.append(OperationBlocker(
                    reasonES: "Bloqueado: no se pueden eliminar todas las copias de un grupo (\(kept.fileName)).",
                    reasonEN: "Blocked: cannot delete every copy in a duplicate group (\(kept.fileName))."
                ))
                continue
            }

            protectedSamples.append(kept.path)
            if sel.group.likelyContainsAPFSClones { anyCloneDetected = true }
            let groupReclaimed = sel.group.estimatedReclaimableBytes(
                deletingPaths: targetSet,
                protectedPath: kept.path
            )
            estimatedReclaimed = ByteTotals.adding(estimatedReclaimed, groupReclaimed)

            for path in cleanTargets {
                guard let file = sel.group.files.first(where: { $0.path == path }) else { continue }
                if file.volumeIsAPFS { anyAPFS = true }

                var blockES: String?
                var blockEN: String?
                if scope.isPathProtectedOrSensitive(file.path) {
                    blockES = "La ruta seleccionada está protegida o fuera del alcance autorizado."
                    blockEN = "Selected copy is protected or outside authorized scope."
                    blockers.append(OperationBlocker(
                        resourceID: file.id,
                        reasonES: blockES!,
                        reasonEN: blockEN!
                    ))
                } else {
                    selectedBytes = ByteTotals.adding(selectedBytes, file.allocatedBytes)
                    totalLogical = ByteTotals.adding(totalLogical, file.logicalBytes)
                }

                resources.append(OperationAffectedResource(
                    id: file.id,
                    labelES: "\(file.fileName) (duplicado · SHA-256 \(String(file.sha256.prefix(8))))",
                    labelEN: "\(file.fileName) (duplicate · SHA-256 \(String(file.sha256.prefix(8))))",
                    pathOrIdentifier: file.path,
                    sizeBytes: file.allocatedBytes,
                    logicalBytes: file.logicalBytes,
                    sizeBasis: .measured,
                    mechanism: .trash,
                    blockedReasonES: blockES,
                    blockedReasonEN: blockEN
                ))
            }
        }

        let actionable = resources.filter { !$0.isBlocked }
        if actionable.isEmpty && blockers.isEmpty {
            blockers.append(OperationBlocker(
                reasonES: "Selecciona al menos una copia sobrante manteniendo al menos una copia protegida por grupo.",
                reasonEN: "Select at least one surplus copy while keeping at least one protected copy per group."
            ))
        }

        let keptList = protectedSamples.prefix(6).joined(separator: ", ")
        let sizeNoteES: String
        let sizeNoteEN: String
        if anyCloneDetected || anyAPFS {
            sizeNoteES = "Tamaño de copias seleccionadas: \(Formatting.bytes(selectedBytes)). Recuperación real estimada: \(Formatting.bytes(estimatedReclaimed)). En volúmenes APFS, los archivos clonados (clonefile) comparten bloques hasta que se eliminan todos los clones o se modifican."
            sizeNoteEN = "Selected copies size: \(Formatting.bytes(selectedBytes)). Estimated actual freed space: \(Formatting.bytes(estimatedReclaimed)). On APFS volumes, cloned files (clonefile) share physical blocks until all clones are deleted or overwritten."
        } else {
            sizeNoteES = "Tamaño medido exacto de las copias seleccionadas (\(Formatting.bytes(selectedBytes))); todas son copias independientes por contenido e inodo."
            sizeNoteEN = "Measured size of selected independent duplicate copies (\(Formatting.bytes(selectedBytes))); hardlinks and clones sharing extents were excluded."
        }

        return OperationPlan(
            domain: .exactDuplicates,
            titleES: "Mover \(actionable.count) copia(s) duplicada(s) a la Papelera",
            titleEN: "Move \(actionable.count) duplicate copy(ies) to Trash",
            scopeDescriptionES: "Solo se mueven las copias sobrantes elegidas tras revalidar el hash SHA-256 e identidad de la copia conservada y de cada copia seleccionada.",
            scopeDescriptionEN: "Only chosen surplus copies move to Trash after re-verifying SHA-256 content and identity of both the kept copy and each surplus file.",
            affectedResources: resources,
            preservedSummaryES: "Se conserva al menos 1 copia protegida por cada grupo (\(keptList.isEmpty ? "copias seleccionadas" : keptList)).",
            preservedSummaryEN: "At least 1 protected copy remains untouched in every group (\(keptList.isEmpty ? "selected kept copies" : keptList)).",
            totalBytes: estimatedReclaimed,
            logicalBytes: totalLogical,
            sizeBasis: anyAPFS ? .mixed : .measured,
            sizeNoteES: sizeNoteES,
            sizeNoteEN: sizeNoteEN,
            regenerationES: "Cada archivo se conserva íntegro en la copia protegida y en la Papelera hasta que la vacíes.",
            regenerationEN: "Content remains preserved both in the kept original copy and in Trash until emptied.",
            mechanism: .trash,
            restorability: .trashRestore,
            restorabilityNoteES: "Las copias sobrantes se envían a la Papelera de macOS para poder restaurarlas si cambias de opinión.",
            restorabilityNoteEN: "Surplus copies move to macOS Trash and can be restored from Trash.",
            blockers: blockers,
            canExecute: !actionable.isEmpty
        )
    }

    public func execute(
        plan: OperationPlan,
        selections: [DuplicateGroupSelection],
        cancellation: CancellationFlag = CancellationFlag()
    ) throws -> OperationExecutionReport {
        guard lock.try() else {
            throw BrisaError.rejected("Another duplicate cleanup is already running")
        }
        defer { lock.unlock() }
        guard plan.domain == .exactDuplicates, plan.canExecute else {
            throw BrisaError.rejected("Duplicate cleanup plan cannot execute")
        }

        _ = try journal.entries()
        let planEntry = try OperationJournalRecorder.recordPlan(plan, journal: journal, home: home)

        var completed: [String] = []
        var rejected: [String] = []
        var failed: [String] = []
        var skipped: [String] = []
        var entries: [JournalEntry] = [planEntry]
        var reclaimedEstimate: Int64 = 0
        var cancelledDuringRun = false

        outer: for sel in selections {
            guard let kept = sel.group.files.first(where: { $0.path == sel.protectedFilePath }) else {
                for p in sel.surplusFilePaths where p != sel.protectedFilePath { rejected.append(p) }
                continue
            }

            let surplusEntries = sel.group.files.filter {
                sel.surplusFilePaths.contains($0.path) && $0.path != kept.path
            }
            guard !surplusEntries.isEmpty, surplusEntries.count < sel.group.files.count else {
                continue
            }

            // Before acting on any surplus copy in this group, strictly re-verify kept copy's identity AND SHA-256!
            let keptValid = verifyFileIdentityAndSHA256(kept, cancellation: cancellation)
            if cancellation.isCancelled {
                cancelledDuringRun = true
                skipped.append(contentsOf: surplusEntries.map(\.path))
                break outer
            }

            if !keptValid {
                for file in surplusEntries {
                    var rej = JournalEntry(
                        operation: "duplicates.trash",
                        originalPath: file.path,
                        size: file.logicalBytes,
                        allocatedBytes: file.allocatedBytes,
                        identity: file.identity,
                        status: OperationOutcomeStatus.rejected.rawValue,
                        error: "Protected kept copy changed or went missing during review",
                        freeSpaceBefore: OperationJournalRecorder.currentAvailableCapacity(for: home),
                        freeSpaceAfter: OperationJournalRecorder.currentAvailableCapacity(for: home),
                        domain: OperationDomain.exactDuplicates.rawValue,
                        mechanism: OperationMechanism.trash.rawValue,
                        restorable: false,
                        planID: plan.id,
                        outcomeKind: OperationOutcomeStatus.rejected.rawValue
                    )
                    rej.summaryTitle = file.fileName
                    try journal.append(rej)
                    entries.append(rej)
                    rejected.append(file.path)
                }
                continue
            }

            for (idx, file) in surplusEntries.enumerated() {
                if cancellation.isCancelled {
                    cancelledDuringRun = true
                    skipped.append(contentsOf: surplusEntries[idx...].map(\.path))
                    break outer
                }

                let freeBefore = OperationJournalRecorder.currentAvailableCapacity(for: home)
                var itemEntry = JournalEntry(
                    operation: "duplicates.trash",
                    originalPath: file.path,
                    size: file.logicalBytes,
                    allocatedBytes: file.allocatedBytes,
                    identity: file.identity,
                    status: "intent",
                    freeSpaceBefore: freeBefore,
                    domain: OperationDomain.exactDuplicates.rawValue,
                    mechanism: OperationMechanism.trash.rawValue,
                    restorable: false,
                    planID: plan.id,
                    summaryTitle: file.fileName
                )

                // Revalidate protected scope, non-symlink, lstat identity, open handles, and exact SHA-256
                guard !scope.isPathProtectedOrSensitive(file.path),
                      verifyFileIdentityAndSHA256(file, cancellation: cancellation),
                      let openPIDs = try? ProcessInspector.openPIDs(file.path),
                      openPIDs.isEmpty else {
                    itemEntry.status = OperationOutcomeStatus.rejected.rawValue
                    itemEntry.outcomeKind = OperationOutcomeStatus.rejected.rawValue
                    itemEntry.error = "File modified, opened, or protected after duplicate analysis"
                    itemEntry.freeSpaceAfter = OperationJournalRecorder.currentAvailableCapacity(for: home)
                    try journal.append(itemEntry)
                    entries.append(itemEntry)
                    rejected.append(file.path)
                    continue
                }

                // Re-confirm kept copy did not link to same inode & still exists intact right before move
                guard kept.identity != file.identity,
                      verifyFileIdentityAndSHA256(kept, cancellation: cancellation) else {
                    itemEntry.status = OperationOutcomeStatus.rejected.rawValue
                    itemEntry.outcomeKind = OperationOutcomeStatus.rejected.rawValue
                    itemEntry.error = "Protected copy invariance failed before Trash move"
                    itemEntry.freeSpaceAfter = OperationJournalRecorder.currentAvailableCapacity(for: home)
                    try journal.append(itemEntry)
                    entries.append(itemEntry)
                    rejected.append(file.path)
                    continue
                }

                do {
                    try journal.append(itemEntry)
                    let dest = try mover.move(URL(fileURLWithPath: file.path))
                    itemEntry.trashPath = dest?.path
                    itemEntry.status = "trashed"
                    itemEntry.outcomeKind = OperationOutcomeStatus.completed.rawValue
                    itemEntry.restorable = true
                    itemEntry.freeSpaceAfter = OperationJournalRecorder.currentAvailableCapacity(for: home)
                    try journal.append(itemEntry)
                    entries.append(itemEntry)
                    completed.append(file.path)
                    if !(file.physicalExtentOffset != nil && file.physicalExtentOffset == kept.physicalExtentOffset && (file.physicalExtentOffset ?? 0) > 0) {
                        reclaimedEstimate = ByteTotals.adding(reclaimedEstimate, file.allocatedBytes)
                    }
                } catch {
                    itemEntry.status = OperationOutcomeStatus.failed.rawValue
                    itemEntry.outcomeKind = OperationOutcomeStatus.failed.rawValue
                    itemEntry.error = error.localizedDescription
                    itemEntry.freeSpaceAfter = OperationJournalRecorder.currentAvailableCapacity(for: home)
                    try journal.append(itemEntry)
                    entries.append(itemEntry)
                    failed.append(file.path)
                }
            }
        }

        let outcome = OperationJournalRecorder.resolveBatchOutcome(
            completed: completed.count,
            rejected: rejected.count,
            failed: failed.count,
            cancelled: cancelledDuringRun
        )
        let detail = cancelledDuringRun && !completed.isEmpty
            ? "\(completed.count) duplicate(s) trashed; cancelled before \(skipped.count) remaining. Already trashed files were not rolled back."
            : "\(completed.count) completed, \(rejected.count) rejected, \(failed.count) failed, \(skipped.count) cancelled."
        let detailES = cancelledDuringRun && !completed.isEmpty
            ? "\(completed.count) copia(s) enviada(s) a Papelera; cancelado antes de \(skipped.count) restante(s). Lo ya movido no se revirtió."
            : "\(completed.count) completado(s), \(rejected.count) rechazado(s), \(failed.count) fallido(s), \(skipped.count) cancelado(s)."
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
            summaryES = "Se enviaron \(completed.count) copia(s) duplicada(s) a la Papelera."
            summaryEN = "Moved \(completed.count) duplicate copy(ies) to Trash."
        case .partial:
            summaryES = "Resultado parcial: \(completed.count) enviada(s) a Papelera, \(rejected.count + failed.count + skipped.count) omitida(s). Lo ya enviado no se revirtió."
            summaryEN = "Partial outcome: \(completed.count) moved to Trash, \(rejected.count + failed.count + skipped.count) skipped. Completed Trash moves were not rolled back."
        case .cancelled:
            summaryES = "Operación cancelada antes de mover copias duplicadas."
            summaryEN = "Operation cancelled before moving duplicate copies."
        case .rejected:
            summaryES = "Las copias fueron rechazadas al revalidar su contenido o la copia conservada."
            summaryEN = "Copies were rejected after content/kept-copy revalidation."
        case .failed, .planned:
            summaryES = "No se pudieron mover las copias duplicadas."
            summaryEN = "Failed while moving duplicate copies."
        }

        return OperationExecutionReport(
            planID: plan.id,
            domain: .exactDuplicates,
            outcome: outcome,
            mechanism: .trash,
            restorable: !completed.isEmpty,
            completedItems: completed,
            rejectedItems: rejected,
            failedItems: failed,
            skippedOnCancellation: skipped,
            reclaimedBytesEstimate: reclaimedEstimate,
            summaryES: summaryES,
            summaryEN: summaryEN,
            journalEntries: entries
        )
    }

    private func verifyFileIdentityAndSHA256(_ entry: DuplicateFileEntry, cancellation: CancellationFlag? = nil) -> Bool {
        guard (try? SafetyPolicy.rejectSymlinks(entry.path)) != nil else { return false }
        var st = stat()
        guard lstat(entry.path, &st) == 0,
              (st.st_mode & S_IFMT) == S_IFREG,
              SafetyPolicy.identity(st) == entry.identity else {
            return false
        }
        let control = cancellation.map { ScanControl(cancellation: $0) } ?? ScanControl()
        guard let liveDigest = ExactDuplicateScanner.streamingSHA256(
            path: entry.path,
            expectedIdentity: entry.identity,
            control: control
        ) else {
            return false
        }
        return liveDigest == entry.sha256
    }
}
