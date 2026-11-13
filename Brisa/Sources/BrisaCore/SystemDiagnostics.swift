import Foundation
import Darwin

public enum DiagnosticAvailability: String, Codable, CaseIterable, Sendable {
    case available = "available"
    case unknown = "unknown"
}

public enum MemoryPressureLevel: String, Codable, CaseIterable, Sendable {
    case normal = "normal"
    case warning = "warning"
    case critical = "critical"
    case unknown = "unknown"
}

public struct SwapDiagnostic: Codable, Equatable, Sendable {
    public let status: DiagnosticAvailability
    public let source: String
    public let unit: String
    public let timestamp: Date
    public let totalBytes: UInt64?
    public let usedBytes: UInt64?
    public let freeBytes: UInt64?
    public let encrypted: Bool?
    public let includedInReclaimableSpace: Bool

    public init(
        status: DiagnosticAvailability,
        source: String = "sysctl vm.swapusage",
        unit: String = "bytes",
        timestamp: Date = Date(),
        totalBytes: UInt64? = nil,
        usedBytes: UInt64? = nil,
        freeBytes: UInt64? = nil,
        encrypted: Bool? = nil
    ) {
        self.status = status
        self.source = source
        self.unit = unit
        self.timestamp = timestamp
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.freeBytes = freeBytes
        self.encrypted = encrypted
        self.includedInReclaimableSpace = false
    }
}

public struct MemoryPressureDiagnostic: Codable, Equatable, Sendable {
    public let status: DiagnosticAvailability
    public let source: String
    public let unit: String
    public let timestamp: Date
    public let rawKernelLevel: Int32?
    public let level: MemoryPressureLevel
    public let compressedBytes: UInt64?
    public let pageins: UInt64?
    public let pageouts: UInt64?
    public let note: String

    public init(
        status: DiagnosticAvailability,
        source: String = "sysctl kern.memorystatus_vm_pressure_level + Mach HOST_VM_INFO64",
        unit: String = "level + bytes",
        timestamp: Date = Date(),
        rawKernelLevel: Int32? = nil,
        level: MemoryPressureLevel = .unknown,
        compressedBytes: UInt64? = nil,
        pageins: UInt64? = nil,
        pageouts: UInt64? = nil,
        note: String = "Presión de memoria del kernel; independiente de la RAM usada."
    ) {
        self.status = status
        self.source = source
        self.unit = unit
        self.timestamp = timestamp
        self.rawKernelLevel = rawKernelLevel
        self.level = level
        self.compressedBytes = compressedBytes
        self.pageins = pageins
        self.pageouts = pageouts
        self.note = note
    }
}

public struct LocalSnapshotsDiagnostic: Codable, Equatable, Sendable {
    public let status: DiagnosticAvailability
    public let source: String
    public let unit: String
    public let timestamp: Date
    public let totalCount: Int?
    public let timeMachineCount: Int?
    public let osUpdateCount: Int?
    public let otherCount: Int?
    public let snapshotNames: [String]
    public let includedInReclaimableSpace: Bool
    public let note: String

    public init(
        status: DiagnosticAvailability,
        source: String = "tmutil listlocalsnapshots /",
        unit: String = "count",
        timestamp: Date = Date(),
        totalCount: Int? = nil,
        timeMachineCount: Int? = nil,
        osUpdateCount: Int? = nil,
        otherCount: Int? = nil,
        snapshotNames: [String] = [],
        note: String = "Diagnóstico de solo lectura; las instantáneas APFS las gestiona macOS/Time Machine y no se suman al espacio limpiable."
    ) {
        self.status = status
        self.source = source
        self.unit = unit
        self.timestamp = timestamp
        self.totalCount = totalCount
        self.timeMachineCount = timeMachineCount
        self.osUpdateCount = osUpdateCount
        self.otherCount = otherCount
        self.snapshotNames = snapshotNames
        self.includedInReclaimableSpace = false
        self.note = note
    }
}

public struct SystemDiagnosticsSnapshot: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let swap: SwapDiagnostic
    public let memoryPressure: MemoryPressureDiagnostic
    public let localSnapshots: LocalSnapshotsDiagnostic

    public init(
        timestamp: Date = Date(),
        swap: SwapDiagnostic,
        memoryPressure: MemoryPressureDiagnostic,
        localSnapshots: LocalSnapshotsDiagnostic
    ) {
        self.timestamp = timestamp
        self.swap = swap
        self.memoryPressure = memoryPressure
        self.localSnapshots = localSnapshots
    }
}

public enum SystemDiagnostics {
    /// Collects swap usage via `sysctlbyname("vm.swapusage", ...)` with fallback to `sysctl vm.swapusage`.
    public static func sampleSwap(now: Date = Date()) -> SwapDiagnostic {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0,
           size == MemoryLayout<xsw_usage>.size {
            let encrypted = usage.xsu_encrypted != 0
            return SwapDiagnostic(
                status: .available,
                source: "sysctlbyname(vm.swapusage)",
                unit: "bytes",
                timestamp: now,
                totalBytes: usage.xsu_total,
                usedBytes: usage.xsu_used,
                freeBytes: usage.xsu_avail,
                encrypted: encrypted
            )
        }

        if let res = try? CommandRunner.run("/usr/sbin/sysctl", ["-n", "vm.swapusage"], timeout: 2.0),
           res.status == 0, !res.timedOut,
           let parsed = parseSwapUsageString(res.output, now: now) {
            return parsed
        }

        return SwapDiagnostic(status: .unknown, timestamp: now)
    }

    /// Parses `sysctl vm.swapusage` text output such as:
    /// `total = 2048.00M  used = 512.25M  free = 1535.75M  (encrypted)`
    public static func parseSwapUsageString(_ text: String, now: Date = Date()) -> SwapDiagnostic? {
        func extractMegabytes(label: String) -> UInt64? {
            guard let range = text.range(of: "\(label)\\s*=\\s*([0-9]+(?:[.,][0-9]+)?)\\s*([KMGTP]?)", options: .regularExpression) else {
                return nil
            }
            let match = String(text[range])
            guard let eqIndex = match.firstIndex(of: "=") else { return nil }
            let rhs = match[match.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)
            let unitChar = rhs.last?.uppercased() ?? "M"
            let numberPart = rhs.trimmingCharacters(in: CharacterSet(charactersIn: "KMGTPkmgtp ")).replacingOccurrences(of: ",", with: ".")
            guard let value = Double(numberPart) else { return nil }
            let multiplier: Double
            switch unitChar {
            case "K": multiplier = 1024.0
            case "M": multiplier = 1024.0 * 1024.0
            case "G": multiplier = 1024.0 * 1024.0 * 1024.0
            case "T": multiplier = 1024.0 * 1024.0 * 1024.0 * 1024.0
            default: multiplier = 1024.0 * 1024.0
            }
            let bytes = (value * multiplier).rounded()
            guard bytes.isFinite, bytes >= 0, bytes < Double(UInt64.max) else { return nil }
            return UInt64(bytes)
        }

        guard let total = extractMegabytes(label: "total"),
              let used = extractMegabytes(label: "used"),
              let free = extractMegabytes(label: "free") else {
            return nil
        }
        let encrypted = text.lowercased().contains("encrypted")
        return SwapDiagnostic(
            status: .available,
            source: "sysctl vm.swapusage",
            unit: "bytes",
            timestamp: now,
            totalBytes: total,
            usedBytes: used,
            freeBytes: free,
            encrypted: encrypted
        )
    }

    /// Collects kernel memory pressure level via `sysctlbyname("kern.memorystatus_vm_pressure_level", ...)`
    /// alongside compressed memory and paging counters from Mach `HOST_VM_INFO64`.
    public static func sampleMemoryPressure(now: Date = Date()) -> MemoryPressureDiagnostic {
        var vm = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmStatus = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount)
            }
        }
        var pageSize: vm_size_t = 0
        let hasVM = (vmStatus == KERN_SUCCESS && host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS)
        return sampleMemoryPressure(now: now, vmStatistics: hasVM ? vm : nil, pageSize: pageSize)
    }

    /// Reuses an already-sampled Mach `vm_statistics64` struct to avoid duplicate `HOST_VM_INFO64` syscalls.
    public static func sampleMemoryPressure(
        now: Date = Date(),
        vmStatistics vm: vm_statistics64?,
        pageSize: vm_size_t
    ) -> MemoryPressureDiagnostic {
        var rawLevel: Int32 = 0
        var levelSize = MemoryLayout<Int32>.size
        let hasKernelLevel = sysctlbyname("kern.memorystatus_vm_pressure_level", &rawLevel, &levelSize, nil, 0) == 0

        let compressedBytes: UInt64? = vm.map { UInt64($0.compressor_page_count) * UInt64(pageSize) }
        let pageins: UInt64? = vm.map { UInt64($0.pageins) }
        let pageouts: UInt64? = vm.map { UInt64($0.pageouts) }

        guard hasKernelLevel else {
            return MemoryPressureDiagnostic(
                status: .unknown,
                timestamp: now,
                rawKernelLevel: nil,
                level: .unknown,
                compressedBytes: compressedBytes,
                pageins: pageins,
                pageouts: pageouts
            )
        }

        let mapped = mapKernelPressureLevel(rawLevel)
        return MemoryPressureDiagnostic(
            status: .available,
            timestamp: now,
            rawKernelLevel: rawLevel,
            level: mapped,
            compressedBytes: compressedBytes,
            pageins: pageins,
            pageouts: pageouts
        )
    }

    public static func mapKernelPressureLevel(_ rawLevel: Int32) -> MemoryPressureLevel {
        switch rawLevel {
        case 1: return .normal
        case 2: return .warning
        case 4: return .critical
        default: return .unknown
        }
    }

    /// Inspects APFS local snapshots on `/` in read-only mode via `/usr/sbin/tmutil listlocalsnapshots /`.
    /// Never deletes or thins snapshots.
    public static func sampleLocalSnapshots(
        tmutilExecutable: String = "/usr/sbin/tmutil",
        mountPoint: String = "/",
        timeout: TimeInterval = 3.0,
        now: Date = Date()
    ) -> LocalSnapshotsDiagnostic {
        guard FileManager.default.isExecutableFile(atPath: tmutilExecutable),
              let res = try? CommandRunner.run(tmutilExecutable, ["listlocalsnapshots", mountPoint], timeout: timeout),
              res.status == 0, !res.timedOut else {
            return LocalSnapshotsDiagnostic(
                status: .unknown,
                source: "tmutil listlocalsnapshots \(mountPoint)",
                unit: "count",
                timestamp: now
            )
        }
        return parseTmutilLocalSnapshots(res.output, mountPoint: mountPoint, now: now)
    }

    /// Parses the output of `tmutil listlocalsnapshots /`.
    public static func parseTmutilLocalSnapshots(
        _ output: String,
        mountPoint: String = "/",
        now: Date = Date()
    ) -> LocalSnapshotsDiagnostic {
        var names: [String] = []
        var tmCount = 0
        var osUpdateCount = 0
        var otherCount = 0

        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.lowercased().hasPrefix("snapshots for ") {
                continue
            }
            if line.hasPrefix("com.apple.") || line.contains(".local") || line.contains("20") {
                names.append(line)
                if line.hasPrefix("com.apple.TimeMachine.") {
                    tmCount += 1
                } else if line.hasPrefix("com.apple.os.update") {
                    osUpdateCount += 1
                } else {
                    otherCount += 1
                }
            }
        }

        let total = names.count
        return LocalSnapshotsDiagnostic(
            status: .available,
            source: "tmutil listlocalsnapshots \(mountPoint)",
            unit: "count",
            timestamp: now,
            totalCount: total,
            timeMachineCount: tmCount,
            osUpdateCount: osUpdateCount,
            otherCount: otherCount,
            snapshotNames: names
        )
    }

    public static func collectAll(includeLocalSnapshots: Bool = true, now: Date = Date()) -> SystemDiagnosticsSnapshot {
        let swap = sampleSwap(now: now)
        let pressure = sampleMemoryPressure(now: now)
        let snapshots = includeLocalSnapshots
            ? sampleLocalSnapshots(now: now)
            : LocalSnapshotsDiagnostic(status: .unknown, timestamp: now)
        return SystemDiagnosticsSnapshot(
            timestamp: now,
            swap: swap,
            memoryPressure: pressure,
            localSnapshots: snapshots
        )
    }
}
