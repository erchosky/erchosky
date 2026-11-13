import Foundation

/// All segments use the same denominator. Small segments are never removed or rescaled.
struct MenuDiskUsage: Equatable {
    let total: Int64
    let used: Int64
    let other: Int64
    let scanned: Int64
    let eligible: Int64

    init?(totalBytes: Int64?, freeBytes: Int64?, scannedBytes: Int64, eligibleBytes: Int64) {
        guard let total = totalBytes, let free = freeBytes, total > 0, (0...total).contains(free) else { return nil }
        self.total = total
        used = total - free
        let measured = min(max(0, scannedBytes), used)
        eligible = min(max(0, eligibleBytes), measured)
        scanned = measured - eligible
        other = used - measured
    }

    func fraction(_ bytes: Int64) -> Double { Double(bytes) / Double(total) }
}
