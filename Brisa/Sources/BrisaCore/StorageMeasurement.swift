import Foundation
import Darwin

public struct InodeKey: Hashable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public init(device: UInt64, inode: UInt64) {
        self.device = device
        self.inode = inode
    }
}

public struct MeasurementResult: Equatable, Sendable {
    public let path: String
    public let isDirectory: Bool
    public let identity: FileIdentity
    public let allocatedBytes: Int64
    public let logicalBytes: Int64
    public let virtualCapacityBytes: Int64?
    public let childCount: Int
    public let modifiedAt: Date
    public let dateKind: String
    public let isPartial: Bool
    public let partialReason: String?
    public let accessDeniedCount: Int
    public let containsSymlink: Bool
    public let containsNestedGit: Bool
    public let skippedProtectedChild: Bool

    public init(
        path: String,
        isDirectory: Bool,
        identity: FileIdentity,
        allocatedBytes: Int64,
        logicalBytes: Int64,
        virtualCapacityBytes: Int64?,
        childCount: Int,
        modifiedAt: Date,
        dateKind: String,
        isPartial: Bool,
        partialReason: String? = nil,
        accessDeniedCount: Int,
        containsSymlink: Bool = false,
        containsNestedGit: Bool = false,
        skippedProtectedChild: Bool = false
    ) {
        self.path = path
        self.isDirectory = isDirectory
        self.identity = identity
        self.allocatedBytes = allocatedBytes
        self.logicalBytes = logicalBytes
        self.virtualCapacityBytes = virtualCapacityBytes
        self.childCount = childCount
        self.modifiedAt = modifiedAt
        self.dateKind = dateKind
        self.isPartial = isPartial
        self.partialReason = partialReason
        self.accessDeniedCount = accessDeniedCount
        self.containsSymlink = containsSymlink
        self.containsNestedGit = containsNestedGit
        self.skippedProtectedChild = skippedProtectedChild
    }
}

public enum StorageMeasurement {
    private static let rawVMDiskExtensions: Set<String> = [
        "raw", "img"
    ]
    private static let rawVMDiskNames: Set<String> = [
        "docker.raw", "disk", "datadisk", "rootfs.img", "sessiondata.img", "data.img"
    ]

    public static func measure(
        path: String,
        category: StorageCategory,
        readPolicy: ReadAuthorizationPolicy,
        claimedPaths: Set<String>,
        neverTouchedPaths: Set<String>,
        seenInodes: inout Set<InodeKey>,
        cancellation: CancellationFlag,
        maxEntriesPerItem: Int = 25_000,
        examinedCounter: inout Int,
        deadline: Date = .distantFuture
    ) -> MeasurementResult? {
        guard maxEntriesPerItem > 0, !cancellation.isCancelled, Date() < deadline else { return nil }
        guard readPolicy.evaluate(path, checkSymlinks: true) == .allowed,
              !readPolicy.requiresUnauthedTCCPrompt(path) else { return nil }
        var rootStat = stat()
        guard lstat(path, &rootStat) == 0 else { return nil }
        let mode = rootStat.st_mode & S_IFMT
        guard mode == S_IFREG || mode == S_IFDIR else { return nil }

        let rootIdentity = SafetyPolicy.identity(rootStat)
        let rootModified = Date(timeIntervalSince1970: rootIdentity.modified)

        if mode == S_IFREG {
            let key = InodeKey(device: rootIdentity.device, inode: rootIdentity.inode)
            guard seenInodes.insert(key).inserted else { return nil }
            examinedCounter += 1
            let allocated = Int64(rootStat.st_blocks) * 512
            let logical = Int64(rootStat.st_size)
            let vCap = inspectVMDiskVirtualCapacity(path: path, category: category, logical: logical, allocated: allocated)
            return MeasurementResult(
                path: path,
                isDirectory: false,
                identity: rootIdentity,
                allocatedBytes: allocated,
                logicalBytes: logical,
                virtualCapacityBytes: vCap,
                childCount: 1,
                modifiedAt: rootModified,
                dateKind: "mtime_file",
                isPartial: false,
                partialReason: nil,
                accessDeniedCount: 0
            )
        }

        // Directory or bundle measurement via iterative stack using POSIX opendir/readdir/lstat
        let remainingDeadline = deadline.timeIntervalSinceNow
        if remainingDeadline <= 0 { return nil }
        let deadlineUptime: UInt64 = remainingDeadline >= 86_400
            ? .max
            : DispatchTime.now().uptimeNanoseconds &+ UInt64(remainingDeadline * 1_000_000_000)

        var allocatedTotal: Int64 = 0
        var logicalTotal: Int64 = 0
        var virtualCapacityTotal: Int64 = 0
        var virtualCapacityOverflow = false
        var hasVMDisk = false
        var fileCount = 0
        var latestModifiedTime = rootIdentity.modified
        var isPartial = false
        var hitEntryLimit = false
        var hitTimeLimit = false
        var byteOverflow = false
        var accessDenied = 0
        var localExamined = 0
        var containsSymlink = false
        var containsNestedGit = false
        var skippedProtectedChild = false

        var stack: [String] = [path]
        while let currentDir = stack.popLast() {
            let nowUptime = deadlineUptime == .max ? 0 : DispatchTime.now().uptimeNanoseconds
            if cancellation.isCancelled || nowUptime >= deadlineUptime || localExamined >= maxEntriesPerItem {
                isPartial = true
                hitEntryLimit = localExamined >= maxEntriesPerItem
                hitTimeLimit = nowUptime >= deadlineUptime
                break
            }

            if readPolicy.requiresUnauthedTCCPrompt(currentDir) {
                accessDenied += 1
                isPartial = true
                continue
            }
            guard let dir = Paths.openDirectory(currentDir) else {
                isPartial = true
                if errno == EACCES || errno == EPERM {
                    accessDenied += 1
                    isPartial = true
                }
                continue
            }
            defer { closedir(dir) }

            let isRootPrefix = currentDir == "/"
            while let entry = readdir(dir) {
                let entryUptime = deadlineUptime == .max ? 0 : DispatchTime.now().uptimeNanoseconds
                if cancellation.isCancelled || entryUptime >= deadlineUptime || localExamined >= maxEntriesPerItem {
                    isPartial = true
                    hitEntryLimit = localExamined >= maxEntriesPerItem
                    hitTimeLimit = entryUptime >= deadlineUptime
                    break
                }

                let name = withUnsafePointer(to: entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                        String(cString: $0)
                    }
                }
                if name == "." || name == ".." || name == ".DS_Store" { continue }
                localExamined += 1
                examinedCounter += 1
                if name == ".git" { containsNestedGit = true }

                let childPath = isRootPrefix ? "/\(name)" : "\(currentDir)/\(name)"
                if (!claimedPaths.isEmpty && claimedPaths.contains(childPath)) ||
                   (!neverTouchedPaths.isEmpty && Paths.containsAncestor(of: childPath, in: neverTouchedPaths)) {
                    continue
                }
                switch readPolicy.evaluateChildForMeasurement(childPath) {
                case .allowed:
                    break
                case .tccPromptRequired:
                    accessDenied += 1
                    isPartial = true
                    continue
                case .denied:
                    skippedProtectedChild = true
                    continue
                }

                var st = stat()
                guard lstat(childPath, &st) == 0 else {
                    isPartial = true
                    if errno == EACCES || errno == EPERM {
                        accessDenied += 1
                    }
                    continue
                }

                let childMode = st.st_mode & S_IFMT
                if childMode == S_IFLNK {
                    containsSymlink = true
                    // Never follow or count symbolic links
                    continue
                } else if childMode == S_IFDIR {
                    stack.append(childPath)
                } else if childMode == S_IFREG {
                    let inoKey = InodeKey(device: UInt64(UInt32(bitPattern: st.st_dev)), inode: st.st_ino)
                    guard seenInodes.insert(inoKey).inserted else { continue }

                    let fileAlloc = Int64(st.st_blocks) * 512
                    let fileLogical = Int64(st.st_size)
                    let allocatedSum = allocatedTotal.addingReportingOverflow(fileAlloc)
                    let logicalSum = logicalTotal.addingReportingOverflow(fileLogical)
                    byteOverflow = byteOverflow || allocatedSum.overflow || logicalSum.overflow
                    allocatedTotal = allocatedSum.overflow ? Int64.max : allocatedSum.partialValue
                    logicalTotal = logicalSum.overflow ? Int64.max : logicalSum.partialValue
                    if byteOverflow { isPartial = true }
                    fileCount += 1

                    let modTime = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9
                    if modTime > latestModifiedTime {
                        latestModifiedTime = modTime
                    }

                    if let vCap = inspectVMDiskVirtualCapacity(path: childPath, category: category, logical: fileLogical, allocated: fileAlloc) {
                        hasVMDisk = true
                        let sum = virtualCapacityTotal.addingReportingOverflow(vCap)
                        if sum.overflow { virtualCapacityOverflow = true }
                        else { virtualCapacityTotal = sum.partialValue }
                    }
                }
            }
        }

        // Skip completely empty 0-byte directories unless access was denied
        if fileCount == 0 && allocatedTotal == 0 && logicalTotal == 0 && accessDenied == 0 && !isPartial {
            return nil
        }

        let syntheticIdentity = FileIdentity(
            device: rootIdentity.device,
            inode: rootIdentity.inode,
            size: logicalTotal,
            modified: latestModifiedTime,
            changed: rootIdentity.changed,
            links: rootIdentity.links,
            mode: rootIdentity.mode,
            owner: rootIdentity.owner
        )

        let virtualCap: Int64? = (hasVMDisk && !virtualCapacityOverflow && virtualCapacityTotal > 0) ? virtualCapacityTotal : nil
        let partialReason: String? = {
            guard isPartial else { return nil }
            var reasons: [String] = []
            if cancellation.isCancelled { reasons.append("cancelled") }
            if hitTimeLimit { reasons.append("time_budget_reached") }
            if hitEntryLimit { reasons.append("entry_budget_reached(\(localExamined)/\(maxEntriesPerItem))") }
            if accessDenied > 0 { reasons.append("permission_denied(\(accessDenied))") }
            if byteOverflow { reasons.append("byte_total_overflow") }
            return reasons.isEmpty ? "partial_measurement" : reasons.joined(separator: ";")
        }()

        return MeasurementResult(
            path: path,
            isDirectory: true,
            identity: syntheticIdentity,
            allocatedBytes: allocatedTotal,
            logicalBytes: logicalTotal,
            virtualCapacityBytes: virtualCap,
            childCount: fileCount,
            modifiedAt: Date(timeIntervalSince1970: latestModifiedTime),
            dateKind: "mtime_latest_entry",
            isPartial: isPartial,
            partialReason: partialReason,
            accessDeniedCount: accessDenied,
            containsSymlink: containsSymlink,
            containsNestedGit: containsNestedGit,
            skippedProtectedChild: skippedProtectedChild
        )
    }

    /// Determines declared virtual capacity for a VM disk file without confusing container length (`st_size`)
    /// with declared guest disk size.
    /// - For `.qcow2`, reads only the 32-byte QCOW2 v2/v3 header (`QFI\xfb` magic + big-endian uint64 at offset 24).
    /// - For raw sparse disk images (`.raw`, `.img`, `docker.raw`, `disk`, `datadisk`), `st_size` (`logical`) is the virtual capacity.
    /// - For container formats without a parsed header (`.vmdk`, `.vdi`, `.vhdx`, `.hdd`, `.iso`) or non-disk files, returns `nil`.
    public static func inspectVMDiskVirtualCapacity(path: String, category: StorageCategory, logical: Int64, allocated: Int64) -> Int64? {
        guard category == .vmContainers else { return nil }
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()

        if ext == "qcow2" {
            return readQCOW2VirtualSize(path: path)
        }
        if rawVMDiskNames.contains(name) || rawVMDiskExtensions.contains(ext) {
            return logical > 0 ? logical : nil
        }
        return nil
    }

    private static func readQCOW2VirtualSize(path: String) -> Int64? {
        let fd = Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_mode & S_IFMT == S_IFREG, st.st_size >= 32 else { return nil }
        var header = [UInt8](repeating: 0, count: 32)
        let bytesRead = pread(fd, &header, 32, 0)
        guard bytesRead == 32 else { return nil }
        // QCOW2 magic: 'Q', 'F', 'I', 0xfb
        guard header[0] == 0x51, header[1] == 0x46, header[2] == 0x49, header[3] == 0xfb else {
            return nil
        }
        let version = (UInt32(header[4]) << 24) | (UInt32(header[5]) << 16) | (UInt32(header[6]) << 8) | UInt32(header[7])
        guard version == 2 || version == 3 else { return nil }
        var virtualSize: UInt64 = 0
        for idx in 24..<32 {
            virtualSize = (virtualSize << 8) | UInt64(header[idx])
        }
        guard virtualSize > 0, virtualSize <= UInt64(Int64.max) else { return nil }
        return Int64(virtualSize)
    }
}
