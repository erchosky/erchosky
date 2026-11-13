import Foundation

/// High-level workflow domain for operation planning and journal auditing.
public enum OperationDomain: String, Codable, CaseIterable, Sendable {
    case cacheInventory = "cache_inventory"
    case projectArtifacts = "project_artifacts"
    case packageManagers = "package_managers"
    case exactDuplicates = "exact_duplicates"
    case appUninstall = "app_uninstall"
    case docker = "docker"
}

/// Deletion or cleanup mechanism used when executing an approved plan.
public enum OperationMechanism: String, Codable, CaseIterable, Sendable {
    case trash = "trash"
    case toolCommand = "tool_command"
    case mixed = "mixed"
}

/// Restorability guarantee communicated prior to confirmation and recorded in the journal.
public enum OperationRestorability: String, Codable, CaseIterable, Sendable {
    case trashRestore = "trash_restore"
    case partialTrashRestore = "partial_trash_restore"
    case irreversible = "irreversible"

    public var admitsRestore: Bool {
        self != .irreversible
    }
}

/// Indicates whether presented byte counts were directly measured on disk or estimated by tooling/layers.
public enum SizeMeasurementBasis: String, Codable, CaseIterable, Sendable {
    case measured = "measured"
    case estimated = "estimated"
    case mixed = "mixed"
}

/// Canonical execution outcome taxonomy persisted in the journal.
public enum OperationOutcomeStatus: String, Codable, CaseIterable, Sendable {
    case planned = "planned"
    case completed = "completed"
    case rejected = "rejected"
    case failed = "failed"
    case cancelled = "cancelled"
    case partial = "partial"
}

/// Concrete item or resource referenced inside a reviewable `OperationPlan`.
public struct OperationAffectedResource: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let labelES: String
    public let labelEN: String
    public let pathOrIdentifier: String
    public let sizeBytes: Int64?
    public let logicalBytes: Int64?
    public let sizeBasis: SizeMeasurementBasis
    public let mechanism: OperationMechanism
    public let blockedReasonES: String?
    public let blockedReasonEN: String?

    public var isBlocked: Bool {
        blockedReasonES != nil || blockedReasonEN != nil
    }

    public init(
        id: String,
        labelES: String,
        labelEN: String,
        pathOrIdentifier: String,
        sizeBytes: Int64? = nil,
        logicalBytes: Int64? = nil,
        sizeBasis: SizeMeasurementBasis = .measured,
        mechanism: OperationMechanism = .trash,
        blockedReasonES: String? = nil,
        blockedReasonEN: String? = nil
    ) {
        self.id = id
        self.labelES = labelES
        self.labelEN = labelEN
        self.pathOrIdentifier = pathOrIdentifier
        self.sizeBytes = sizeBytes
        self.logicalBytes = logicalBytes
        self.sizeBasis = sizeBasis
        self.mechanism = mechanism
        self.blockedReasonES = blockedReasonES
        self.blockedReasonEN = blockedReasonEN
    }
}

/// Precondition or lock preventing execution (or preventing a specific subset) until resolved.
public struct OperationBlocker: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let resourceID: String?
    public let reasonES: String
    public let reasonEN: String
    public let canRecheck: Bool

    public init(
        id: String = UUID().uuidString,
        resourceID: String? = nil,
        reasonES: String,
        reasonEN: String,
        canRecheck: Bool = false
    ) {
        self.id = id
        self.resourceID = resourceID
        self.reasonES = reasonES
        self.reasonEN = reasonEN
        self.canRecheck = canRecheck
    }
}

/// Reviewable operation plan presented to the user before executing any cleanup or removal.
public struct OperationPlan: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: Date
    public let domain: OperationDomain
    public let titleES: String
    public let titleEN: String
    public let scopeDescriptionES: String
    public let scopeDescriptionEN: String
    public let affectedResources: [OperationAffectedResource]
    public let preservedSummaryES: String
    public let preservedSummaryEN: String
    public let totalBytes: Int64?
    public let logicalBytes: Int64?
    public let sizeBasis: SizeMeasurementBasis
    public let sizeNoteES: String?
    public let sizeNoteEN: String?
    public let regenerationES: String
    public let regenerationEN: String
    public let mechanism: OperationMechanism
    public let restorability: OperationRestorability
    public let restorabilityNoteES: String
    public let restorabilityNoteEN: String
    public let blockers: [OperationBlocker]
    public let requiresExplicitVolumeUnlock: Bool
    public let canExecute: Bool

    public var actionableResources: [OperationAffectedResource] {
        affectedResources.filter { !$0.isBlocked }
    }

    public var blockedResources: [OperationAffectedResource] {
        affectedResources.filter(\.isBlocked)
    }

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        domain: OperationDomain,
        titleES: String,
        titleEN: String,
        scopeDescriptionES: String,
        scopeDescriptionEN: String,
        affectedResources: [OperationAffectedResource],
        preservedSummaryES: String,
        preservedSummaryEN: String,
        totalBytes: Int64?,
        logicalBytes: Int64? = nil,
        sizeBasis: SizeMeasurementBasis,
        sizeNoteES: String? = nil,
        sizeNoteEN: String? = nil,
        regenerationES: String,
        regenerationEN: String,
        mechanism: OperationMechanism,
        restorability: OperationRestorability,
        restorabilityNoteES: String,
        restorabilityNoteEN: String,
        blockers: [OperationBlocker],
        requiresExplicitVolumeUnlock: Bool = false,
        canExecute: Bool
    ) {
        self.id = id
        self.createdAt = createdAt
        self.domain = domain
        self.titleES = titleES
        self.titleEN = titleEN
        self.scopeDescriptionES = scopeDescriptionES
        self.scopeDescriptionEN = scopeDescriptionEN
        self.affectedResources = affectedResources
        self.preservedSummaryES = preservedSummaryES
        self.preservedSummaryEN = preservedSummaryEN
        self.totalBytes = totalBytes
        self.logicalBytes = logicalBytes
        self.sizeBasis = sizeBasis
        self.sizeNoteES = sizeNoteES
        self.sizeNoteEN = sizeNoteEN
        self.regenerationES = regenerationES
        self.regenerationEN = regenerationEN
        self.mechanism = mechanism
        self.restorability = restorability
        self.restorabilityNoteES = restorabilityNoteES
        self.restorabilityNoteEN = restorabilityNoteEN
        self.blockers = blockers
        self.requiresExplicitVolumeUnlock = requiresExplicitVolumeUnlock
        self.canExecute = canExecute
    }
}

/// Structured execution result distinguishing completed, rejected, failed, cancelled, and partial runs.
public struct OperationExecutionReport: Codable, Equatable, Sendable {
    public let planID: String
    public let domain: OperationDomain
    public let outcome: OperationOutcomeStatus
    public let mechanism: OperationMechanism
    public let restorable: Bool
    public let completedItems: [String]
    public let rejectedItems: [String]
    public let failedItems: [String]
    public let skippedOnCancellation: [String]
    public let reclaimedBytesEstimate: Int64?
    public let summaryES: String
    public let summaryEN: String
    public let commandOutput: String?
    public let journalEntries: [JournalEntry]

    public init(
        planID: String,
        domain: OperationDomain,
        outcome: OperationOutcomeStatus,
        mechanism: OperationMechanism,
        restorable: Bool,
        completedItems: [String] = [],
        rejectedItems: [String] = [],
        failedItems: [String] = [],
        skippedOnCancellation: [String] = [],
        reclaimedBytesEstimate: Int64? = nil,
        summaryES: String,
        summaryEN: String,
        commandOutput: String? = nil,
        journalEntries: [JournalEntry] = []
    ) {
        self.planID = planID
        self.domain = domain
        self.outcome = outcome
        self.mechanism = mechanism
        self.restorable = restorable
        self.completedItems = completedItems
        self.rejectedItems = rejectedItems
        self.failedItems = failedItems
        self.skippedOnCancellation = skippedOnCancellation
        self.reclaimedBytesEstimate = reclaimedBytesEstimate
        self.summaryES = summaryES
        self.summaryEN = summaryEN
        self.commandOutput = commandOutput
        self.journalEntries = journalEntries
    }
}

/// Records reviewable operation plans and honest execution outcomes into the hash-chained journal.
public enum OperationJournalRecorder {
    public static func currentAvailableCapacity(for path: String) -> Int64? {
        if let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeAvailableCapacityKey]),
           let free = values.volumeAvailableCapacity {
            return Int64(free)
        }
        return nil
    }

    @discardableResult
    public static func recordPlan(_ plan: OperationPlan, journal: Journal, home: String) throws -> JournalEntry {
        let primaryPath = plan.actionableResources.first?.pathOrIdentifier
            ?? plan.affectedResources.first?.pathOrIdentifier
            ?? plan.domain.rawValue
        let entry = JournalEntry(
            id: "plan-\(plan.id)",
            operation: "\(plan.domain.rawValue).plan",
            originalPath: primaryPath,
            size: plan.logicalBytes ?? plan.totalBytes ?? 0,
            allocatedBytes: plan.totalBytes,
            status: OperationOutcomeStatus.planned.rawValue,
            freeSpaceBefore: currentAvailableCapacity(for: home),
            domain: plan.domain.rawValue,
            mechanism: plan.mechanism.rawValue,
            restorable: plan.restorability.admitsRestore,
            planID: plan.id,
            outcomeKind: OperationOutcomeStatus.planned.rawValue,
            summaryTitle: plan.titleEN,
            summaryTitleES: plan.titleES,
            detailNote: plan.scopeDescriptionEN,
            detailNoteES: plan.scopeDescriptionES
        )
        try journal.append(entry)
        return entry
    }

    @discardableResult
    public static func finalizePlan(
        _ plan: OperationPlan,
        planEntry: JournalEntry,
        outcome: OperationOutcomeStatus,
        completedCount: Int,
        skippedOrFailedCount: Int,
        errorText: String? = nil,
        detailNote: String,
        detailNoteES: String? = nil,
        restorable: Bool,
        journal: Journal,
        home: String
    ) throws -> JournalEntry {
        var finalEntry = planEntry
        finalEntry.date = Date()
        finalEntry.status = outcome.rawValue
        finalEntry.outcomeKind = outcome.rawValue
        finalEntry.error = errorText
        finalEntry.restorable = restorable
        finalEntry.detailNote = detailNote
        if let detailNoteES {
            finalEntry.detailNoteES = detailNoteES
        }
        finalEntry.completedCount = completedCount
        finalEntry.skippedOrFailedCount = skippedOrFailedCount
        finalEntry.freeSpaceAfter = currentAvailableCapacity(for: home)
        try journal.append(finalEntry)
        return finalEntry
    }

    /// Computes final batch outcome cleanly so partial progress + cancellation is never hidden or falsely rolled back.
    public static func resolveBatchOutcome(
        completed: Int,
        rejected: Int,
        failed: Int,
        cancelled: Bool
    ) -> OperationOutcomeStatus {
        let unfinished = rejected + failed
        if cancelled {
            return completed > 0 ? .partial : .cancelled
        }
        if completed > 0 && unfinished == 0 {
            return .completed
        }
        if completed > 0 && unfinished > 0 {
            return .partial
        }
        if failed > 0 {
            return .failed
        }
        if rejected > 0 {
            return .rejected
        }
        return .rejected
    }
}
