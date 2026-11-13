import Foundation
import Darwin

public struct MetricsSnapshot: Codable, Sendable {
    public var date = Date()
    public var cpuPercent: Double?
    public var memoryUsed: UInt64?
    public var memoryTotal: UInt64
    public var diskFree: Int64?
    public var diskTotal: Int64?
    public var gpuPercent: Double? = nil
    public var diskHealth: String = "unavailable"
    public var cpuBasis = "host tick delta"
    public var memoryBasis = "active + wired + compressed pages; not memory pressure"
    public var swap: SwapDiagnostic?
    public var memoryPressure: MemoryPressureDiagnostic?
    public var localSnapshots: LocalSnapshotsDiagnostic?
}

public final class MetricsSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var previous: [UInt32]?
    private var cachedSnapshots: LocalSnapshotsDiagnostic?
    private var lastSnapshotCheck: Date?

    public init() {}

    /// Clears previous CPU tick baseline so stale idle/sleep intervals are never treated as active sampling windows.
    public func resetCPUBaseline() {
        lock.lock()
        previous = nil
        lock.unlock()
    }

    public func sample(forceRefreshSnapshots: Bool = false) -> MetricsSnapshot {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        var result = MetricsSnapshot(memoryTotal: ProcessInfo.processInfo.physicalMemory)
        result.date = now
        var cpu = host_cpu_load_info(), count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &cpu) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        if status == KERN_SUCCESS {
            let ticks = [cpu.cpu_ticks.0, cpu.cpu_ticks.1, cpu.cpu_ticks.2, cpu.cpu_ticks.3]
            if let old = previous {
                let delta = zip(ticks, old).map { UInt64($0 &- $1) }
                let total = delta.reduce(0, +)
                if total > 0 { result.cpuPercent = 100 * Double(total - delta[Int(CPU_STATE_IDLE)]) / Double(total) }
            }
            previous = ticks
        }
        var vm = vm_statistics64(), vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmStatus = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount) }
        }
        var pageSize: vm_size_t = 0
        let hasVM = vmStatus == KERN_SUCCESS && host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS
        if hasVM {
            result.memoryUsed = (UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)) * UInt64(pageSize)
        }
        if let volume = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey]) {
            result.diskFree = volume.volumeAvailableCapacity.map(Int64.init)
            result.diskTotal = volume.volumeTotalCapacity.map(Int64.init)
        }

        result.swap = SystemDiagnostics.sampleSwap(now: now)
        result.memoryPressure = SystemDiagnostics.sampleMemoryPressure(now: now, vmStatistics: hasVM ? vm : nil, pageSize: pageSize)

        if forceRefreshSnapshots || cachedSnapshots == nil || (lastSnapshotCheck.map { now.timeIntervalSince($0) >= 60 } ?? true) {
            cachedSnapshots = SystemDiagnostics.sampleLocalSnapshots(now: now)
            lastSnapshotCheck = now
        }
        result.localSnapshots = cachedSnapshots

        return result
    }
}
