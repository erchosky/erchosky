import Foundation

public enum InventoryMetadata {
    /// Rechecking metadata never grants broader eligibility than the indexed catalog decision.
    public static func refresh(_ file: IndexedFile, readPolicy: ReadAuthorizationPolicy,
                               claimedPaths: Set<String> = []) throws -> IndexedFile {
        var seen = Set<InodeKey>()
        var count = 0
        guard let measured = StorageMeasurement.measure(path: file.path, category: file.storageCategory,
            readPolicy: readPolicy, claimedPaths: claimedPaths, neverTouchedPaths: [], seenInodes: &seen,
            cancellation: CancellationFlag(), maxEntriesPerItem: 2_000, examinedCounter: &count,
            deadline: Date().addingTimeInterval(2)) else {
            throw BrisaError.unavailable("Item unavailable or outside authorized scope; refresh the inventory")
        }
        guard measured.identity == file.identity else {
            throw BrisaError.rejected("Item changed since analysis; refresh the inventory")
        }
        var updated = file
        updated.allocatedBytes = measured.allocatedBytes
        updated.logicalBytes = measured.logicalBytes
        updated.virtualCapacityBytes = measured.virtualCapacityBytes
        updated.isPartial = measured.isPartial
        updated.partialReason = measured.partialReason
        if measured.isPartial {
            updated.eligible = false
            updated.selectionAllowed = false
            updated.inventoryOnly = true
            updated.reclaimableBytes = 0
            updated.cleanupEligibility = .lockedUnverifiedCondition
        }
        return updated
    }
}
