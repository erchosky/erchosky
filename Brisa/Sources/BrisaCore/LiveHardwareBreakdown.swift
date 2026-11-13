import Darwin
import Foundation
import IOKit

public enum LiveResourceKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case memory
    case cpu
    case gpu

    public var id: String { rawValue }
}

public enum ResourceConsumerKind: String, Codable, Sendable, Equatable {
    case system
    case app
    case other
}

public struct ResourceConsumerEntry: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var kind: ResourceConsumerKind
    public var displayName: String
    public var bundlePath: String?
    public var processCount: Int
    public var primaryBytes: UInt64?
    public var percent: Double?
    public var rawCoreCPUPercent: Double?
    public var gpuDeltaNanoseconds: UInt64?

    public init(
        id: String,
        kind: ResourceConsumerKind,
        displayName: String,
        bundlePath: String? = nil,
        processCount: Int = 1,
        primaryBytes: UInt64? = nil,
        percent: Double? = nil,
        rawCoreCPUPercent: Double? = nil,
        gpuDeltaNanoseconds: UInt64? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.bundlePath = bundlePath
        self.processCount = processCount
        self.primaryBytes = primaryBytes
        self.percent = percent
        self.rawCoreCPUPercent = rawCoreCPUPercent
        self.gpuDeltaNanoseconds = gpuDeltaNanoseconds
    }
}

public enum GPUActivityStatus: String, Codable, Sendable, Equatable {
    case available
    case warmingUp = "warming_up"
    case idle
    case unavailable
}

public struct HardwareBreakdownSnapshot: Codable, Sendable {
    public var sampledAt: Date
    public var metrics: MetricsSnapshot
    public var cpuCoreCount: Int
    public var gpuUtilizationPercent: Double?
    public var gpuRendererUtilizationPercent: Double?
    public var gpuTilerUtilizationPercent: Double?
    public var gpuInUseSystemMemoryBytes: UInt64?
    public var gpuAllocatedSystemMemoryBytes: UInt64?
    public var totalObservedProcessRSSBytes: UInt64?
    public var gpuDeltaIntervalSeconds: Double?
    public var gpuStatus: GPUActivityStatus
    public var memoryConsumers: [ResourceConsumerEntry]
    public var cpuConsumers: [ResourceConsumerEntry]
    public var gpuConsumers: [ResourceConsumerEntry]

    public init(
        sampledAt: Date = Date(),
        metrics: MetricsSnapshot,
        cpuCoreCount: Int = ProcessInfo.processInfo.activeProcessorCount,
        gpuUtilizationPercent: Double? = nil,
        gpuRendererUtilizationPercent: Double? = nil,
        gpuTilerUtilizationPercent: Double? = nil,
        gpuInUseSystemMemoryBytes: UInt64? = nil,
        gpuAllocatedSystemMemoryBytes: UInt64? = nil,
        totalObservedProcessRSSBytes: UInt64? = nil,
        gpuDeltaIntervalSeconds: Double? = nil,
        gpuStatus: GPUActivityStatus = .unavailable,
        memoryConsumers: [ResourceConsumerEntry] = [],
        cpuConsumers: [ResourceConsumerEntry] = [],
        gpuConsumers: [ResourceConsumerEntry] = []
    ) {
        self.sampledAt = sampledAt
        self.metrics = metrics
        self.cpuCoreCount = max(1, cpuCoreCount)
        self.gpuUtilizationPercent = gpuUtilizationPercent
        self.gpuRendererUtilizationPercent = gpuRendererUtilizationPercent
        self.gpuTilerUtilizationPercent = gpuTilerUtilizationPercent
        self.gpuInUseSystemMemoryBytes = gpuInUseSystemMemoryBytes
        self.gpuAllocatedSystemMemoryBytes = gpuAllocatedSystemMemoryBytes
        self.totalObservedProcessRSSBytes = totalObservedProcessRSSBytes
        self.gpuDeltaIntervalSeconds = gpuDeltaIntervalSeconds
        self.gpuStatus = gpuStatus
        self.memoryConsumers = memoryConsumers
        self.cpuConsumers = cpuConsumers
        self.gpuConsumers = gpuConsumers
    }
}

/// Raw process entry parsed from `/bin/ps` or live kernel/libproc sampling for resource attribution.
public struct ParsedProcessSample: Sendable, Equatable {
    public var pid: Int32
    public var ppid: Int32
    public var uid: UInt32
    public var rawCPUPercent: Double
    public var rssBytes: UInt64
    public var commandPath: String
    public var startTimeMicros: UInt64?

    public init(
        pid: Int32,
        ppid: Int32,
        uid: UInt32,
        rawCPUPercent: Double,
        rssBytes: UInt64,
        commandPath: String,
        startTimeMicros: UInt64? = nil
    ) {
        self.pid = pid
        self.ppid = ppid
        self.uid = uid
        self.rawCPUPercent = rawCPUPercent
        self.rssBytes = rssBytes
        self.commandPath = commandPath
        self.startTimeMicros = startTimeMicros
    }
}

public struct GPUClientUsageSample: Sendable, Equatable {
    public var pid: Int32
    public var creatorName: String
    public var accumulatedGPUNanoseconds: UInt64

    public init(pid: Int32, creatorName: String, accumulatedGPUNanoseconds: UInt64) {
        self.pid = pid
        self.creatorName = creatorName
        self.accumulatedGPUNanoseconds = accumulatedGPUNanoseconds
    }
}

public struct IOAcceleratorTelemetry: Sendable, Equatable {
    public var deviceUtilizationPercent: Double?
    public var rendererUtilizationPercent: Double?
    public var tilerUtilizationPercent: Double?
    public var inUseSystemMemoryBytes: UInt64?
    public var allocatedSystemMemoryBytes: UInt64?
    public var clientAccumulatedGPUNanoseconds: [Int32: GPUClientUsageSample]

    public init(
        deviceUtilizationPercent: Double? = nil,
        rendererUtilizationPercent: Double? = nil,
        tilerUtilizationPercent: Double? = nil,
        inUseSystemMemoryBytes: UInt64? = nil,
        allocatedSystemMemoryBytes: UInt64? = nil,
        clientAccumulatedGPUNanoseconds: [Int32: GPUClientUsageSample] = [:]
    ) {
        self.deviceUtilizationPercent = deviceUtilizationPercent
        self.rendererUtilizationPercent = rendererUtilizationPercent
        self.tilerUtilizationPercent = tilerUtilizationPercent
        self.inUseSystemMemoryBytes = inUseSystemMemoryBytes
        self.allocatedSystemMemoryBytes = allocatedSystemMemoryBytes
        self.clientAccumulatedGPUNanoseconds = clientAccumulatedGPUNanoseconds
    }
}

/// Real-time telemetry & per-application breakdown sampler.
/// Preserves zero fabricated fallbacks: unavailable hardware counters stay `nil`.
public final class LiveHardwareBreakdownSampler: @unchecked Sendable {
    private struct PreviousCPUSample {
        let totalMachTicks: UInt64
        let startTimeMicros: UInt64
    }

    private struct PreviousGPUSample {
        let accumulatedGPUNanoseconds: UInt64
        let creatorName: String
        let startTimeMicros: UInt64?
    }

    private let lock = NSLock()
    private let metricsSampler: MetricsSampler
    private var previousGPUTimes: [Int32: PreviousGPUSample]?
    private var previousGPUSampleAt: Date?
    private var previousCPUTimes: [Int32: PreviousCPUSample]?
    private var previousCPUSampleUptimeNs: UInt64?

    public init(metricsSampler: MetricsSampler = MetricsSampler()) {
        self.metricsSampler = metricsSampler
    }

    /// Clears cached CPU and GPU interval baselines (for example after sleep or hiding telemetry surfaces).
    public func resetBaseline() {
        lock.withLock {
            previousGPUTimes = nil
            previousGPUSampleAt = nil
            previousCPUTimes = nil
            previousCPUSampleUptimeNs = nil
        }
        metricsSampler.resetCPUBaseline()
    }

    /// Samples host CPU/memory/GPU counters and groups live processes and Metal clients
    /// into `macOS`, parent `.app` bundles, and `other`.
    public func sample(
        now: Date = Date(),
        maxVisibleConsumers: Int = 6,
        otherLabel: String = "Otros",
        systemLabel: String = "macOS"
    ) -> HardwareBreakdownSnapshot {
        let baseMetrics = metricsSampler.sample(forceRefreshSnapshots: false)
        let prevCPUState = lock.withLock { (previousCPUTimes, previousCPUSampleUptimeNs) }
        let sampleUptimeNs = DispatchTime.now().uptimeNanoseconds
        let procResult = Self.readProcessSamples(
            previousCPUTimes: prevCPUState.0,
            previousUptimeNs: prevCPUState.1,
            currentUptimeNs: sampleUptimeNs
        )
        let processes = procResult.samples
        let processStartByPID = procResult.startTimesByPID
        let gpuTelemetry = Self.readIOAcceleratorTelemetry()

        let previousGPU = lock.withLock { () -> ([Int32: UInt64]?, Date?) in
            previousCPUTimes = procResult.nextCPUTimes
            previousCPUSampleUptimeNs = sampleUptimeNs

            var filteredPrev: [Int32: UInt64]? = nil
            if let prior = previousGPUTimes {
                var valid: [Int32: UInt64] = [:]
                valid.reserveCapacity(prior.count)
                for (pid, entry) in prior {
                    if let currentSample = gpuTelemetry?.clientAccumulatedGPUNanoseconds[pid] {
                        let currentStart = processStartByPID[pid]
                        let sameStart = (entry.startTimeMicros == nil || currentStart == nil || entry.startTimeMicros == currentStart)
                        let sameCreator = (entry.creatorName == currentSample.creatorName)
                        if sameStart && sameCreator {
                            valid[pid] = entry.accumulatedGPUNanoseconds
                        }
                    }
                }
                filteredPrev = valid
            }
            let prevAt = previousGPUSampleAt

            if let gpuTelemetry {
                var nextMap: [Int32: PreviousGPUSample] = [:]
                nextMap.reserveCapacity(gpuTelemetry.clientAccumulatedGPUNanoseconds.count)
                for (pid, sample) in gpuTelemetry.clientAccumulatedGPUNanoseconds {
                    nextMap[pid] = PreviousGPUSample(
                        accumulatedGPUNanoseconds: sample.accumulatedGPUNanoseconds,
                        creatorName: sample.creatorName,
                        startTimeMicros: processStartByPID[pid]
                    )
                }
                previousGPUTimes = nextMap
                previousGPUSampleAt = now
            }
            return (filteredPrev, prevAt)
        }

        return Self.buildSnapshot(
            now: now,
            metrics: baseMetrics,
            processes: processes,
            currentUID: getuid(),
            gpuTelemetry: gpuTelemetry,
            previousGPUTimes: previousGPU.0,
            previousGPUSampleAt: previousGPU.1,
            maxVisibleConsumers: maxVisibleConsumers,
            otherLabel: otherLabel,
            systemLabel: systemLabel
        )
    }

    // MARK: - Pure Attribution & Aggregation Builders (Unit Tested)

    public static func buildSnapshot(
        now: Date = Date(),
        metrics: MetricsSnapshot,
        processes: [ParsedProcessSample],
        currentUID: UInt32,
        gpuTelemetry: IOAcceleratorTelemetry?,
        previousGPUTimes: [Int32: UInt64]?,
        previousGPUSampleAt: Date?,
        cpuCoreCount: Int = ProcessInfo.processInfo.activeProcessorCount,
        maxVisibleConsumers: Int = 6,
        otherLabel: String = "Otros",
        systemLabel: String = "macOS"
    ) -> HardwareBreakdownSnapshot {
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var attributionCache: [Int32: AttributionTarget] = [:]

        func resolve(_ pid: Int32, fallbackName: String? = nil) -> AttributionTarget {
            if let cached = attributionCache[pid] { return cached }
            let target = resolveAttribution(pid: pid, byPID: byPID, currentUID: currentUID, fallbackName: fallbackName, systemLabel: systemLabel)
            attributionCache[pid] = target
            return target
        }

        let totalObservedRSS = processes.reduce(UInt64(0)) { $0 &+ $1.rssBytes }
        let memoryConsumers = buildMemoryConsumers(
            processes: processes,
            metrics: metrics,
            resolve: { resolve($0) },
            maxVisibleConsumers: maxVisibleConsumers,
            otherLabel: otherLabel
        )

        let resolvedCores = max(1, cpuCoreCount)
        let cpuConsumers = buildCPUConsumers(
            processes: processes,
            cpuCoreCount: resolvedCores,
            resolve: { resolve($0) },
            maxVisibleConsumers: maxVisibleConsumers,
            otherLabel: otherLabel
        )

        let gpuDeltaInterval: Double? = previousGPUSampleAt.map { max(0.01, now.timeIntervalSince($0)) }
        let (gpuStatus, gpuConsumers) = buildGPUConsumers(
            gpuTelemetry: gpuTelemetry,
            previousGPUTimes: previousGPUTimes,
            resolve: { pid, fallbackName in resolve(pid, fallbackName: fallbackName) },
            maxVisibleConsumers: maxVisibleConsumers,
            otherLabel: otherLabel
        )

        return HardwareBreakdownSnapshot(
            sampledAt: now,
            metrics: metrics,
            cpuCoreCount: resolvedCores,
            gpuUtilizationPercent: gpuTelemetry?.deviceUtilizationPercent,
            gpuRendererUtilizationPercent: gpuTelemetry?.rendererUtilizationPercent,
            gpuTilerUtilizationPercent: gpuTelemetry?.tilerUtilizationPercent,
            gpuInUseSystemMemoryBytes: gpuTelemetry?.inUseSystemMemoryBytes,
            gpuAllocatedSystemMemoryBytes: gpuTelemetry?.allocatedSystemMemoryBytes,
            totalObservedProcessRSSBytes: processes.isEmpty ? nil : totalObservedRSS,
            gpuDeltaIntervalSeconds: gpuDeltaInterval,
            gpuStatus: gpuStatus,
            memoryConsumers: memoryConsumers,
            cpuConsumers: cpuConsumers,
            gpuConsumers: gpuConsumers
        )
    }

    private struct AttributionTarget: Hashable {
        let id: String
        let kind: ResourceConsumerKind
        let displayName: String
        let bundlePath: String?
    }

    private static func resolveAttribution(
        pid: Int32,
        byPID: [Int32: ParsedProcessSample],
        currentUID: UInt32,
        fallbackName: String?,
        systemLabel: String
    ) -> AttributionTarget {
        if let proc = byPID[pid] {
            if isSystemProcess(proc, currentUID: currentUID) {
                return AttributionTarget(id: "system:macos", kind: .system, displayName: systemLabel, bundlePath: nil)
            }
            if let appPath = extractOuterAppBundlePath(from: proc.commandPath) {
                let appName = appDisplayName(forBundlePath: appPath)
                return AttributionTarget(id: "app:\(appPath)", kind: .app, displayName: appName, bundlePath: appPath)
            }
            // Walk ancestor chain up to launchd so helper CLI processes belong to their parent app.
            var cursor = proc.ppid
            var visited: Set<Int32> = [proc.pid]
            var depth = 0
            while cursor > 1 && depth < 10 && !visited.contains(cursor) {
                visited.insert(cursor)
                guard let parent = byPID[cursor] else { break }
                if isSystemProcess(parent, currentUID: currentUID) {
                    break
                }
                if let parentAppPath = extractOuterAppBundlePath(from: parent.commandPath) {
                    let appName = appDisplayName(forBundlePath: parentAppPath)
                    return AttributionTarget(id: "app:\(parentAppPath)", kind: .app, displayName: appName, bundlePath: parentAppPath)
                }
                cursor = parent.ppid
                depth += 1
            }

            let execName = URL(fileURLWithPath: proc.commandPath).lastPathComponent
            let cleanName = execName.isEmpty ? "PID \(pid)" : execName
            return AttributionTarget(id: "cli:\(cleanName)", kind: .other, displayName: cleanName, bundlePath: nil)
        }

        let cleanFallback = fallbackName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (cleanFallback?.isEmpty == false ? cleanFallback! : "PID \(pid)")
        return AttributionTarget(id: "pid:\(pid)", kind: .other, displayName: name, bundlePath: nil)
    }

    public static func isSystemProcess(_ proc: ParsedProcessSample, currentUID: UInt32) -> Bool {
        if proc.pid <= 1 || proc.uid != currentUID {
            return true
        }
        let path = proc.commandPath
        let systemPrefixes = [
            "/System/Library/",
            "/System/DriverExtensions/",
            "/usr/bin/",
            "/usr/sbin/",
            "/usr/libexec/",
            "/usr/lib/",
            "/usr/share/",
            "/sbin/",
            "/bin/",
            "/Library/Apple/"
        ]
        return systemPrefixes.contains { path.hasPrefix($0) }
    }

    /// Returns the outermost `.app` bundle path when helper bundles are nested inside
    /// a parent app (e.g. `Antigravity.app/.../Antigravity Helper.app/...` -> `.../Antigravity.app`).
    public static func extractOuterAppBundlePath(from commandPath: String) -> String? {
        guard commandPath.contains(".app") else { return nil }
        if let range = commandPath.range(of: ".app/") {
            return String(commandPath[..<commandPath.index(range.lowerBound, offsetBy: 4)])
        }
        if commandPath.hasSuffix(".app") {
            return commandPath
        }
        return nil
    }

    private static func appDisplayName(forBundlePath path: String) -> String {
        let url = URL(fileURLWithPath: path)
        return url.deletingPathExtension().lastPathComponent
    }

    private static func buildMemoryConsumers(
        processes: [ParsedProcessSample],
        metrics: MetricsSnapshot,
        resolve: (Int32) -> AttributionTarget,
        maxVisibleConsumers: Int,
        otherLabel: String
    ) -> [ResourceConsumerEntry] {
        guard !processes.isEmpty, metrics.memoryTotal > 0 else { return [] }

        struct Bucket {
            let target: AttributionTarget
            var bytes: UInt64 = 0
            var processCount = 0
        }

        var buckets: [AttributionTarget: Bucket] = [:]

        for proc in processes {
            let target = resolve(proc.pid)
            var bucket = buckets[target] ?? Bucket(target: target)
            bucket.bytes &+= proc.rssBytes
            bucket.processCount += 1
            buckets[target] = bucket
        }

        // Report observed per-process RSS directly; never synthesize host (memoryUsed - sum(RSS))
        // into macOS because RSS overlaps shared pages and excludes kernel/compressor internals.
        let sorted = buckets.values
            .filter { $0.bytes > 0 }
            .sorted { lhs, rhs in
                if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
                return lhs.target.displayName.localizedCaseInsensitiveCompare(rhs.target.displayName) == .orderedAscending
            }

        return consolidateTopConsumers(
            sorted.map { bucket in
                let pct = min(100.0, (Double(bucket.bytes) / Double(metrics.memoryTotal)) * 100.0)
                return ResourceConsumerEntry(
                    id: bucket.target.id,
                    kind: bucket.target.kind,
                    displayName: bucket.target.displayName,
                    bundlePath: bucket.target.bundlePath,
                    processCount: bucket.processCount,
                    primaryBytes: bucket.bytes,
                    percent: pct
                )
            },
            maxVisibleConsumers: maxVisibleConsumers,
            otherLabel: otherLabel,
            aggregateOther: { rest in
                let otherBytes = rest.compactMap(\.primaryBytes).reduce(0, &+)
                let otherCount = rest.map(\.processCount).reduce(0, +)
                let otherPct = min(100.0, (Double(otherBytes) / Double(metrics.memoryTotal)) * 100.0)
                return ResourceConsumerEntry(
                    id: "other:memory",
                    kind: .other,
                    displayName: otherLabel,
                    bundlePath: nil,
                    processCount: otherCount,
                    primaryBytes: otherBytes,
                    percent: otherPct
                )
            }
        )
    }

    private static func buildCPUConsumers(
        processes: [ParsedProcessSample],
        cpuCoreCount: Int,
        resolve: (Int32) -> AttributionTarget,
        maxVisibleConsumers: Int,
        otherLabel: String
    ) -> [ResourceConsumerEntry] {
        guard !processes.isEmpty else { return [] }

        struct Bucket {
            let target: AttributionTarget
            var rawCPU: Double = 0
            var processCount = 0
        }

        var buckets: [AttributionTarget: Bucket] = [:]
        for proc in processes where proc.rawCPUPercent > 0 {
            let target = resolve(proc.pid)
            var bucket = buckets[target] ?? Bucket(target: target)
            bucket.rawCPU += proc.rawCPUPercent
            bucket.processCount += 1
            buckets[target] = bucket
        }

        let cores = Double(max(1, cpuCoreCount))
        let sorted = buckets.values
            .filter { ($0.rawCPU / cores) >= 0.05 }
            .sorted { lhs, rhs in
                if lhs.rawCPU != rhs.rawCPU { return lhs.rawCPU > rhs.rawCPU }
                return lhs.target.displayName.localizedCaseInsensitiveCompare(rhs.target.displayName) == .orderedAscending
            }

        return consolidateTopConsumers(
            sorted.map { bucket in
                ResourceConsumerEntry(
                    id: bucket.target.id,
                    kind: bucket.target.kind,
                    displayName: bucket.target.displayName,
                    bundlePath: bucket.target.bundlePath,
                    processCount: bucket.processCount,
                    primaryBytes: nil,
                    percent: min(100.0, bucket.rawCPU / cores),
                    rawCoreCPUPercent: bucket.rawCPU
                )
            },
            maxVisibleConsumers: maxVisibleConsumers,
            otherLabel: otherLabel,
            aggregateOther: { rest in
                let rawSum = rest.compactMap(\.rawCoreCPUPercent).reduce(0, +)
                let countSum = rest.map(\.processCount).reduce(0, +)
                return ResourceConsumerEntry(
                    id: "other:cpu",
                    kind: .other,
                    displayName: otherLabel,
                    bundlePath: nil,
                    processCount: countSum,
                    primaryBytes: nil,
                    percent: min(100.0, rawSum / cores),
                    rawCoreCPUPercent: rawSum
                )
            }
        )
    }

    private static func buildGPUConsumers(
        gpuTelemetry: IOAcceleratorTelemetry?,
        previousGPUTimes: [Int32: UInt64]?,
        resolve: (Int32, String?) -> AttributionTarget,
        maxVisibleConsumers: Int,
        otherLabel: String
    ) -> (GPUActivityStatus, [ResourceConsumerEntry]) {
        guard let gpuTelemetry else {
            return (.unavailable, [])
        }
        guard gpuTelemetry.deviceUtilizationPercent != nil || !gpuTelemetry.clientAccumulatedGPUNanoseconds.isEmpty else {
            return (.unavailable, [])
        }
        guard let previousGPUTimes else {
            return (.warmingUp, [])
        }

        struct Bucket {
            let target: AttributionTarget
            var deltaNs: UInt64 = 0
            var processCount = 0
        }

        var buckets: [AttributionTarget: Bucket] = [:]
        var totalDeltaNs: UInt64 = 0

        for (pid, sample) in gpuTelemetry.clientAccumulatedGPUNanoseconds {
            let prev = previousGPUTimes[pid] ?? 0
            guard sample.accumulatedGPUNanoseconds > prev else { continue }
            let delta = sample.accumulatedGPUNanoseconds - prev
            totalDeltaNs &+= delta

            let target = resolve(pid, sample.creatorName)
            var bucket = buckets[target] ?? Bucket(target: target)
            bucket.deltaNs &+= delta
            bucket.processCount += 1
            buckets[target] = bucket
        }

        guard totalDeltaNs > 0 else {
            return (.idle, [])
        }

        // Report each client's honest share (%) of observed Metal GPU interval time (deltaNs / totalDeltaNs),
        // distinct from instantaneous IOAccelerator Device Utilization %.
        let sorted = buckets.values
            .filter { $0.deltaNs > 0 }
            .sorted { lhs, rhs in
                if lhs.deltaNs != rhs.deltaNs { return lhs.deltaNs > rhs.deltaNs }
                return lhs.target.displayName.localizedCaseInsensitiveCompare(rhs.target.displayName) == .orderedAscending
            }

        let entries = consolidateTopConsumers(
            sorted.map { bucket in
                let share = (Double(bucket.deltaNs) / Double(totalDeltaNs)) * 100.0
                return ResourceConsumerEntry(
                    id: bucket.target.id,
                    kind: bucket.target.kind,
                    displayName: bucket.target.displayName,
                    bundlePath: bucket.target.bundlePath,
                    processCount: bucket.processCount,
                    primaryBytes: nil,
                    percent: share,
                    gpuDeltaNanoseconds: bucket.deltaNs
                )
            },
            maxVisibleConsumers: maxVisibleConsumers,
            otherLabel: otherLabel,
            aggregateOther: { rest in
                let deltaSum = rest.compactMap(\.gpuDeltaNanoseconds).reduce(0, &+)
                let countSum = rest.map(\.processCount).reduce(0, +)
                let share = (Double(deltaSum) / Double(totalDeltaNs)) * 100.0
                return ResourceConsumerEntry(
                    id: "other:gpu",
                    kind: .other,
                    displayName: otherLabel,
                    bundlePath: nil,
                    processCount: countSum,
                    primaryBytes: nil,
                    percent: share,
                    gpuDeltaNanoseconds: deltaSum
                )
            }
        )

        return (.available, entries)
    }

    private static func consolidateTopConsumers(
        _ sorted: [ResourceConsumerEntry],
        maxVisibleConsumers: Int,
        otherLabel: String,
        aggregateOther: ([ResourceConsumerEntry]) -> ResourceConsumerEntry
    ) -> [ResourceConsumerEntry] {
        guard sorted.count > maxVisibleConsumers, maxVisibleConsumers > 0 else {
            return sorted
        }
        // Preserve top-N actual heaviest consumers (apps, macOS, or standalone CLI tools)
        // and fold the remaining long tail cleanly into a single consolidated "Other" row.
        var head = Array(sorted.prefix(maxVisibleConsumers))
        let tail = Array(sorted.dropFirst(maxVisibleConsumers))
        if !tail.isEmpty {
            let consolidated = aggregateOther(tail)
            if (consolidated.primaryBytes ?? 0) > 0 || (consolidated.percent ?? 0) >= 0.05 || (consolidated.gpuDeltaNanoseconds ?? 0) > 0 {
                head.append(consolidated)
            }
        }
        return head
    }

    // MARK: - Live Process & IOKit Readers

    public static func parseProcessOutput(_ output: String) -> [ParsedProcessSample] {
        var rows: [ParsedProcessSample] = []
        rows.reserveCapacity(256)

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = rawLine.drop(while: { $0 == " " || $0 == "\t" })
            guard !trimmed.isEmpty else { continue }

            var idx = trimmed.startIndex
            func nextToken() -> Substring? {
                while idx < trimmed.endIndex && (trimmed[idx] == " " || trimmed[idx] == "\t") {
                    idx = trimmed.index(after: idx)
                }
                guard idx < trimmed.endIndex else { return nil }
                let start = idx
                while idx < trimmed.endIndex && trimmed[idx] != " " && trimmed[idx] != "\t" {
                    idx = trimmed.index(after: idx)
                }
                return trimmed[start..<idx]
            }

            guard let pidTok = nextToken(), let pid = Int32(pidTok),
                  let ppidTok = nextToken(), let ppid = Int32(ppidTok),
                  let uidTok = nextToken(), let uid = UInt32(uidTok),
                  let cpuTok = nextToken(), let cpu = Double(cpuTok.replacingOccurrences(of: ",", with: ".")),
                  let rssTok = nextToken(), let rssKiB = UInt64(rssTok) else {
                continue
            }

            while idx < trimmed.endIndex && (trimmed[idx] == " " || trimmed[idx] == "\t") {
                idx = trimmed.index(after: idx)
            }
            let commandPath = String(trimmed[idx...])
            rows.append(
                ParsedProcessSample(
                    pid: pid,
                    ppid: ppid,
                    uid: uid,
                    rawCPUPercent: max(0, cpu),
                    rssBytes: rssKiB &* 1024,
                    commandPath: commandPath
                )
            )
        }
        return rows
    }

    public static func parseIOUserClientCreator(_ raw: String) -> (pid: Int32, name: String)? {
        // Standard IOKit format: "pid 423, WindowServer"
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("pid ") else { return nil }
        let afterPrefix = trimmed.dropFirst(4)
        let parts = afterPrefix.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        guard let pidPart = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(pidPart) else {
            return nil
        }
        let creatorName = parts.count > 1
            ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        return (pid, creatorName)
    }

    private static let machTimebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        if info.denom == 0 {
            info.numer = 1
            info.denom = 1
        }
        return info
    }()

    private static func readProcessSamples(
        previousCPUTimes: [Int32: PreviousCPUSample]?,
        previousUptimeNs: UInt64?,
        currentUptimeNs: UInt64
    ) -> (
        samples: [ParsedProcessSample],
        nextCPUTimes: [Int32: PreviousCPUSample],
        startTimesByPID: [Int32: UInt64]
    ) {
        let kernelMeta = readKernelProcessMetadata()
        let wallDeltaNs: UInt64? = previousUptimeNs.flatMap { currentUptimeNs > $0 ? currentUptimeNs - $0 : nil }
        let logicalCores = Double(max(1, ProcessInfo.processInfo.activeProcessorCount))
        let timebaseNumer = Double(machTimebase.numer)
        let timebaseDenom = Double(machTimebase.denom)

        var nextCPUTimes: [Int32: PreviousCPUSample] = [:]
        nextCPUTimes.reserveCapacity(kernelMeta.count)
        var startTimesByPID: [Int32: UInt64] = [:]
        startTimesByPID.reserveCapacity(kernelMeta.count)
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))

        var libprocStats: [Int32: (cpuPercent: Double?, rssBytes: UInt64, commandPath: String)] = [:]
        libprocStats.reserveCapacity(kernelMeta.count)

        for (pid, meta) in kernelMeta {
            startTimesByPID[pid] = meta.startTimeMicros
            let fullPath: String
            let plen = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            if plen > 0, let decoded = String(validatingCString: pathBuffer), !decoded.isEmpty {
                fullPath = decoded
            } else {
                fullPath = meta.comm
            }

            var intervalCPU: Double? = nil
            var taskRSS: UInt64 = 0
            var task = proc_taskinfo()
            let taskSize = Int32(MemoryLayout<proc_taskinfo>.stride)
            if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, taskSize) == taskSize {
                taskRSS = UInt64(task.pti_resident_size)
                let totalTicks = task.pti_total_user &+ task.pti_total_system
                nextCPUTimes[pid] = PreviousCPUSample(
                    totalMachTicks: totalTicks,
                    startTimeMicros: meta.startTimeMicros
                )
                if let wallDeltaNs,
                   wallDeltaNs > 0,
                   let prev = previousCPUTimes?[pid],
                   prev.startTimeMicros == meta.startTimeMicros,
                   totalTicks >= prev.totalMachTicks {
                    let deltaTicks = totalTicks - prev.totalMachTicks
                    let cpuNs = (Double(deltaTicks) * timebaseNumer) / timebaseDenom
                    let pct = 100.0 * cpuNs / Double(wallDeltaNs)
                    intervalCPU = min(logicalCores * 100.0, max(0, pct))
                }
            }
            libprocStats[pid] = (intervalCPU, taskRSS, fullPath)
        }

        // Omit `comm=` so /bin/ps runs roughly 2x faster while supplying system-daemon %cpu & rss;
        // exact command paths and start-time PID-reuse guards come from libproc + sysctl.
        if let result = try? CommandRunner.run("/bin/ps", ["-axo", "pid=,ppid=,uid=,%cpu=,rss="], timeout: 2.0),
           result.status == 0,
           !result.timedOut {
            var rows: [ParsedProcessSample] = []
            rows.reserveCapacity(kernelMeta.count + 32)
            for rawLine in result.output.split(separator: "\n", omittingEmptySubsequences: true) {
                let trimmed = rawLine.drop(while: { $0 == " " || $0 == "\t" })
                guard !trimmed.isEmpty else { continue }
                var idx = trimmed.startIndex
                func nextToken() -> Substring? {
                    while idx < trimmed.endIndex && (trimmed[idx] == " " || trimmed[idx] == "\t") {
                        idx = trimmed.index(after: idx)
                    }
                    guard idx < trimmed.endIndex else { return nil }
                    let start = idx
                    while idx < trimmed.endIndex && trimmed[idx] != " " && trimmed[idx] != "\t" {
                        idx = trimmed.index(after: idx)
                    }
                    return trimmed[start..<idx]
                }
                guard let pidTok = nextToken(), let pid = Int32(pidTok),
                      let ppidTok = nextToken(), let ppid = Int32(ppidTok),
                      let uidTok = nextToken(), let uid = UInt32(uidTok),
                      let cpuTok = nextToken(), let psCPU = Double(cpuTok.replacingOccurrences(of: ",", with: ".")),
                      let rssTok = nextToken(), let rssKiB = UInt64(rssTok) else {
                    continue
                }
                let stat = libprocStats[pid]
                let path = stat?.commandPath ?? kernelMeta[pid]?.comm ?? ""
                let rss = rssKiB > 0 ? (rssKiB &* 1024) : (stat?.rssBytes ?? 0)
                let rawCPU = stat?.cpuPercent ?? max(0, psCPU)
                rows.append(
                    ParsedProcessSample(
                        pid: pid,
                        ppid: ppid,
                        uid: uid,
                        rawCPUPercent: rawCPU,
                        rssBytes: rss,
                        commandPath: path,
                        startTimeMicros: startTimesByPID[pid]
                    )
                )
            }
            if !rows.isEmpty {
                return (rows, nextCPUTimes, startTimesByPID)
            }
        }

        // Graceful fallback if /bin/ps fails or times out: build directly from sysctl + libproc.
        let fallback = kernelMeta.map { pid, meta -> ParsedProcessSample in
            let stat = libprocStats[pid]
            return ParsedProcessSample(
                pid: pid,
                ppid: meta.ppid,
                uid: meta.uid,
                rawCPUPercent: stat?.cpuPercent ?? 0,
                rssBytes: stat?.rssBytes ?? 0,
                commandPath: stat?.commandPath ?? meta.comm,
                startTimeMicros: meta.startTimeMicros
            )
        }
        return (fallback, nextCPUTimes, startTimesByPID)
    }

    private struct KernelProcessMetadata {
        let ppid: Int32
        let uid: UInt32
        let startTimeMicros: UInt64
        let comm: String
    }

    private static func readKernelProcessMetadata() -> [Int32: KernelProcessMetadata] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: Int = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else {
            return [:]
        }
        let capacity = (size / MemoryLayout<kinfo_proc>.stride) + 32
        var kprocs = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
        var actualSize = kprocs.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &kprocs, &actualSize, nil, 0) == 0 else {
            return [:]
        }
        let count = actualSize / MemoryLayout<kinfo_proc>.stride
        var result: [Int32: KernelProcessMetadata] = [:]
        result.reserveCapacity(count)
        for i in 0..<count {
            let kp = kprocs[i]
            let pid = kp.kp_proc.p_pid
            guard pid >= 0 else { continue }
            let startSec = UInt64(max(0, kp.kp_proc.p_starttime.tv_sec))
            let startUsec = UInt64(max(0, kp.kp_proc.p_starttime.tv_usec))
            let startMicros = startSec &* 1_000_000 &+ startUsec
            let comm = withUnsafeBytes(of: kp.kp_proc.p_comm) { raw -> String in
                let prefix = raw.prefix { $0 != 0 }
                return String(decoding: prefix, as: UTF8.self)
            }
            result[pid] = KernelProcessMetadata(
                ppid: kp.kp_eproc.e_ppid,
                uid: kp.kp_eproc.e_ucred.cr_uid,
                startTimeMicros: startMicros,
                comm: comm
            )
        }
        return result
    }

    private static func readIOAcceleratorTelemetry() -> IOAcceleratorTelemetry? {
        guard let matching = IOServiceMatching("IOAccelerator") else {
            return nil
        }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var foundAccelerator = false
        var bestUtilization: Double?
        var bestRenderer: Double?
        var bestTiler: Double?
        var inUseMem: UInt64?
        var allocMem: UInt64?
        var clientSamples: [Int32: GPUClientUsageSample] = [:]

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            foundAccelerator = true

            var propsRef: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = propsRef?.takeRetainedValue() as? [String: Any],
               let perf = dict["PerformanceStatistics"] as? [String: Any] {
                if let val = (perf["Device Utilization %"] as? NSNumber)?.doubleValue {
                    bestUtilization = max(bestUtilization ?? 0, min(100, max(0, val)))
                }
                if let val = (perf["Renderer Utilization %"] as? NSNumber)?.doubleValue {
                    bestRenderer = max(bestRenderer ?? 0, min(100, max(0, val)))
                }
                if let val = (perf["Tiler Utilization %"] as? NSNumber)?.doubleValue {
                    bestTiler = max(bestTiler ?? 0, min(100, max(0, val)))
                }
                if let val = (perf["In use system memory"] as? NSNumber)?.uint64Value {
                    inUseMem = (inUseMem ?? 0) &+ val
                }
                if let val = (perf["Alloc system memory"] as? NSNumber)?.uint64Value {
                    allocMem = (allocMem ?? 0) &+ val
                }
            }

            var childIterator: io_iterator_t = 0
            guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &childIterator) == KERN_SUCCESS else {
                continue
            }
            defer { IOObjectRelease(childIterator) }

            while case let child = IOIteratorNext(childIterator), child != 0 {
                defer { IOObjectRelease(child) }
                var childPropsRef: Unmanaged<CFMutableDictionary>?
                guard IORegistryEntryCreateCFProperties(child, &childPropsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                      let childDict = childPropsRef?.takeRetainedValue() as? [String: Any],
                      let creatorRaw = childDict["IOUserClientCreator"] as? String,
                      let parsedCreator = parseIOUserClientCreator(creatorRaw),
                      let appUsage = childDict["AppUsage"] as? [[String: Any]] else {
                    continue
                }
                let sumNs = appUsage
                    .compactMap { ($0["accumulatedGPUTime"] as? NSNumber)?.uint64Value }
                    .reduce(0, &+)
                guard sumNs > 0 else { continue }

                if var existing = clientSamples[parsedCreator.pid] {
                    existing.accumulatedGPUNanoseconds &+= sumNs
                    clientSamples[parsedCreator.pid] = existing
                } else {
                    clientSamples[parsedCreator.pid] = GPUClientUsageSample(
                        pid: parsedCreator.pid,
                        creatorName: parsedCreator.name,
                        accumulatedGPUNanoseconds: sumNs
                    )
                }
            }
        }

        guard foundAccelerator else { return nil }
        return IOAcceleratorTelemetry(
            deviceUtilizationPercent: bestUtilization,
            rendererUtilizationPercent: bestRenderer,
            tilerUtilizationPercent: bestTiler,
            inUseSystemMemoryBytes: inUseMem,
            allocatedSystemMemoryBytes: allocMem,
            clientAccumulatedGPUNanoseconds: clientSamples
        )
    }
}
