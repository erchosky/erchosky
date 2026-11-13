import Foundation

public enum BrisaError: Error, LocalizedError {
    case rejected(String), io(String), unavailable(String), invalid(String)
    case cancelled
    public var errorDescription: String? {
        switch self {
        case .rejected(let s): return "Safety: \(s)"
        case .io(let s): return "I/O: \(s)"
        case .unavailable(let s): return "Unavailable: \(s)"
        case .invalid(let s): return "Invalid: \(s)"
        case .cancelled: return "Operation cancelled or not confirmed"
        }
    }
    public var code: String {
        switch self { case .rejected: return "safety_rejected"; case .io: return "io_error"
        case .unavailable: return "unavailable"; case .invalid: return "invalid_request"
        case .cancelled: return "cancelled" }
    }
}

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v); case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v); case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v); case .null: try c.encodeNil()
        }
    }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var array: [JSONValue]? { if case .array(let v) = self { return v }; return nil }
    public var object: [String: JSONValue]? { if case .object(let v) = self { return v }; return nil }
    public static func encode<T: Encodable>(_ value: T) throws -> JSONValue {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return try JSONDecoder().decode(JSONValue.self, from: encoder.encode(value))
    }
}

public enum Category: String, Codable, CaseIterable, Sendable { case cache, log, other }
public struct FileIdentity: Codable, Equatable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let size: Int64
    public let modified: TimeInterval
    public let changed: TimeInterval
    public let links: UInt16
    public let mode: UInt16
    public let owner: UInt32

    public init(
        device: UInt64,
        inode: UInt64,
        size: Int64,
        modified: TimeInterval,
        changed: TimeInterval,
        links: UInt16 = 1,
        mode: UInt16 = 0o600,
        owner: UInt32 = 0
    ) {
        self.device = device
        self.inode = inode
        self.size = size
        self.modified = modified
        self.changed = changed
        self.links = links
        self.mode = mode
        self.owner = owner
    }
}
public struct IndexedFile: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let path: String
    public let root: String
    public let identity: FileIdentity
    public var allocatedBytes: Int64
    public let category: Category
    public let modifiedAt: Date
    public var eligible: Bool
    public var reason: String
    public var confidence: String
    public var storageCategory: StorageCategory
    public var titleES: String
    public var titleEN: String
    public var ruleID: String?
    public var sourceGroup: String?
    public var regenBehavior: String?
    public var isDirectory: Bool
    public var childCount: Int
    public var logicalBytes: Int64
    public var virtualCapacityBytes: Int64?
    public var reclaimableBytes: Int64
    public var dataKind: DataTier
    public var inventoryOnly: Bool
    public var selectionAllowed: Bool
    public var cleanupEligibility: CleanupEligibility
    public var usageState: UsageState
    public var dateKind: String
    public var explanationES: String
    public var explanationEN: String
    public var conditionsSummary: [String]
    public var isPartial: Bool
    public var partialReason: String?
    public var provenance: String?
    public var upstreamProvenance: RuleProvenance?
    public var size: Int64 { identity.size }
    /// One selection invariant shared by UI, aggregates, queries and action revalidation.
    public var isReviewable: Bool {
        eligible && selectionAllowed && !inventoryOnly && !isPartial && !isDirectory
            && cleanupEligibility == .eligible && dataKind != .never
    }

    private static let isoFormatterLock = NSLock()
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func iso8601String(_ date: Date) -> String {
        isoFormatterLock.lock()
        defer { isoFormatterLock.unlock() }
        return isoFormatter.string(from: date)
    }

    public func toJSONValue() -> JSONValue {
        var obj: [String: JSONValue] = [
            "id": .string(id),
            "path": .string(path),
            "root": .string(root),
            "identity": .object([
                "device": .number(Double(identity.device)),
                "inode": .number(Double(identity.inode)),
                "size": .number(Double(identity.size)),
                "modified": .number(identity.modified),
                "changed": .number(identity.changed),
                "links": .number(Double(identity.links)),
                "mode": .number(Double(identity.mode)),
                "owner": .number(Double(identity.owner))
            ]),
            "allocatedBytes": .number(Double(allocatedBytes)),
            "category": .string(category.rawValue),
            "modifiedAt": .string(Self.iso8601String(modifiedAt)),
            "eligible": .bool(eligible),
            "reason": .string(reason),
            "confidence": .string(confidence),
            "storageCategory": .string(storageCategory.rawValue),
            "titleES": .string(titleES),
            "titleEN": .string(titleEN),
            "isDirectory": .bool(isDirectory),
            "childCount": .number(Double(childCount)),
            "logicalBytes": .number(Double(logicalBytes)),
            "reclaimableBytes": .number(Double(reclaimableBytes)),
            "dataKind": .string(dataKind.rawValue),
            "inventoryOnly": .bool(inventoryOnly),
            "selectionAllowed": .bool(selectionAllowed),
            "cleanupEligibility": .string(cleanupEligibility.rawValue),
            "usageState": .object(usageState.detail.map {
                ["status": .string(usageState.status), "detail": .string($0)]
            } ?? ["status": .string(usageState.status)]),
            "dateKind": .string(dateKind),
            "explanationES": .string(explanationES),
            "explanationEN": .string(explanationEN),
            "conditionsSummary": .array(conditionsSummary.map(JSONValue.string)),
            "isPartial": .bool(isPartial)
        ]
        if let ruleID { obj["ruleID"] = .string(ruleID) }
        if let sourceGroup { obj["sourceGroup"] = .string(sourceGroup) }
        if let regenBehavior { obj["regenBehavior"] = .string(regenBehavior) }
        if let virtualCapacityBytes { obj["virtualCapacityBytes"] = .number(Double(virtualCapacityBytes)) }
        if let partialReason { obj["partialReason"] = .string(partialReason) }
        if let provenance { obj["provenance"] = .string(provenance) }
        if let up = upstreamProvenance {
            obj["upstreamProvenance"] = .object([
                "repository": .string(up.repository),
                "commit": .string(up.commit),
                "version": .string(up.version),
                "upstreamID": .string(up.upstreamID),
                "upstreamActionKind": .string(up.upstreamActionKind),
                "coverageRelation": .string(up.coverageRelation),
                "localReviewNote": .string(up.localReviewNote)
            ])
        }
        return .object(obj)
    }

    public init(
        id: String,
        path: String,
        root: String,
        identity: FileIdentity,
        allocatedBytes: Int64,
        category: Category,
        modifiedAt: Date,
        eligible: Bool,
        reason: String,
        confidence: String,
        storageCategory: StorageCategory? = nil,
        titleES: String? = nil,
        titleEN: String? = nil,
        ruleID: String? = nil,
        sourceGroup: String? = nil,
        isDirectory: Bool = false,
        childCount: Int = 1,
        logicalBytes: Int64? = nil,
        virtualCapacityBytes: Int64? = nil,
        reclaimableBytes: Int64? = nil,
        dataKind: DataTier? = nil,
        inventoryOnly: Bool? = nil,
        selectionAllowed: Bool? = nil,
        cleanupEligibility: CleanupEligibility? = nil,
        usageState: UsageState = .unknown,
        dateKind: String = "mtime_file",
        explanationES: String? = nil,
        explanationEN: String? = nil,
        conditionsSummary: [String] = [],
        isPartial: Bool = false,
        partialReason: String? = nil,
        provenance: String? = nil,
        upstreamProvenance: RuleProvenance? = nil,
        regenBehavior: String? = nil
    ) {
        self.id = id
        self.path = path
        self.root = root
        self.identity = identity
        self.allocatedBytes = allocatedBytes
        self.category = category
        self.modifiedAt = modifiedAt
        self.eligible = eligible
        self.reason = reason
        self.confidence = confidence
        let inferredCategory: StorageCategory = storageCategory ?? {
            switch category {
            case .cache: return .appCaches
            case .log: return .logsAndCrashes
            case .other: return .appCaches
            }
        }()
        self.storageCategory = inferredCategory
        let fileName = URL(fileURLWithPath: path).lastPathComponent
        self.titleES = titleES ?? fileName
        self.titleEN = titleEN ?? fileName
        self.ruleID = ruleID
        self.sourceGroup = sourceGroup
        self.isDirectory = isDirectory
        self.childCount = childCount
        self.logicalBytes = logicalBytes ?? identity.size
        self.virtualCapacityBytes = virtualCapacityBytes
        self.reclaimableBytes = eligible ? min(allocatedBytes, max(0, reclaimableBytes ?? allocatedBytes)) : 0
        self.dataKind = dataKind ?? (eligible ? .regenerable : .userData)
        self.inventoryOnly = inventoryOnly ?? !eligible
        self.selectionAllowed = selectionAllowed ?? eligible
        self.cleanupEligibility = cleanupEligibility ?? (eligible ? .eligible : .inventoryOnly)
        self.usageState = usageState
        self.dateKind = dateKind
        self.explanationES = explanationES ?? inferredCategory.aboutES
        self.explanationEN = explanationEN ?? inferredCategory.aboutEN
        self.conditionsSummary = conditionsSummary
        self.isPartial = isPartial
        self.partialReason = partialReason
        self.provenance = provenance
        self.upstreamProvenance = upstreamProvenance
        self.regenBehavior = regenBehavior
    }
}
public struct ScanResult: Codable, Sendable {
    public init() {}
    public var files: [IndexedFile] = []
    public var categories: [CategoryReport] = CategoryReport.defaultPending()
    public var catalogSource: String = "swiftpm_module"
    public var roots: [String] = []
    public var inventoryRoots: [String] = []
    public var startedAt = Date()
    public var finishedAt: Date?
    public var complete = false
    public var cancelled = false
    public var isStale = false
    public var staleReason: String?
    public var examined = 0
    public var skipped = 0
    public var errors: [String] = []
    public var measuredBytes: Int64 { files.reduce(0) { ByteTotals.adding($0, $1.allocatedBytes) } }
    public var logicalBytes: Int64 { files.reduce(0) { ByteTotals.adding($0, $1.logicalBytes) } }
    public var candidateBytes: Int64 { files.reduce(0) { $1.isReviewable ? ByteTotals.adding($0, $1.size) : $0 } }
    public var reclaimableAllocatedBytes: Int64 { files.reduce(0) { $1.isReviewable ? ByteTotals.adding($0, $1.allocatedBytes) : $0 } }

    public mutating func rebuildCategoryAggregates() {
        struct Bucket {
            var itemCount = 0
            var eligibleCount = 0
            var allocated: Int64 = 0
            var logical: Int64 = 0
            var reclaimable: Int64 = 0
            var overflow = false
            var hasPartial = false
            var virtualSum: Int64 = 0
            var hasVirtual = false
            var virtualInvalid = false
            var matchedRules: Set<String> = []
        }

        var buckets: [StorageCategory: Bucket] = [:]
        var globalLogical: Int64 = 0
        var globalAlloc: Int64 = 0
        var globalOverflow = false

        for file in files {
            var b = buckets[file.storageCategory] ?? Bucket()
            b.itemCount += 1
            let allocStep = b.allocated.addingReportingOverflow(file.allocatedBytes)
            let logicStep = b.logical.addingReportingOverflow(file.logicalBytes)
            if allocStep.overflow || logicStep.overflow || file.allocatedBytes < 0 || file.logicalBytes < 0 {
                b.overflow = true
            }
            b.allocated = ByteTotals.adding(b.allocated, file.allocatedBytes)
            b.logical = ByteTotals.adding(b.logical, file.logicalBytes)
            if file.isReviewable {
                b.eligibleCount += 1
                b.reclaimable = ByteTotals.adding(b.reclaimable, file.allocatedBytes)
            }
            if file.isPartial { b.hasPartial = true }
            if let vm = file.virtualCapacityBytes {
                b.hasVirtual = true
                if vm < 0 {
                    b.virtualInvalid = true
                } else {
                    let nextVM = b.virtualSum.addingReportingOverflow(vm)
                    if nextVM.overflow { b.virtualInvalid = true } else { b.virtualSum = nextVM.partialValue }
                }
            }
            if let rid = file.ruleID { b.matchedRules.insert(rid) }
            buckets[file.storageCategory] = b

            let gAlloc = globalAlloc.addingReportingOverflow(file.allocatedBytes)
            let gLogic = globalLogical.addingReportingOverflow(file.logicalBytes)
            if gAlloc.overflow || gLogic.overflow || file.allocatedBytes < 0 || file.logicalBytes < 0 {
                globalOverflow = true
            }
            globalAlloc = ByteTotals.adding(globalAlloc, file.allocatedBytes)
            globalLogical = ByteTotals.adding(globalLogical, file.logicalBytes)
        }

        var updated: [CategoryReport] = []
        updated.reserveCapacity(categories.count)
        for var report in categories {
            let previousCount = report.itemCount
            let b = buckets[report.category] ?? Bucket()
            let overflow = b.itemCount > 0 && b.overflow
            let hadPartial = b.hasPartial || overflow
            if overflow && (report.status == .measured || report.status == .partial) {
                report.status = .partial
                report.statusNoteES = "Resultados parciales (tamaño superior al límite representable)"
                report.statusNoteEN = "Partial results (size exceeds representable limit)"
            }
            report.itemCount = b.itemCount
            report.eligibleCount = b.eligibleCount
            report.allocatedBytes = b.allocated
            report.logicalBytes = b.logical
            report.reclaimableBytes = b.reclaimable
            report.virtualCapacityBytes = (b.hasVirtual && !b.virtualInvalid) ? b.virtualSum : nil
            report.matchedRuleCount = b.matchedRules.count
            if report.status == .measured || report.status == .partial {
                if b.itemCount == 0 && !hadPartial && report.status == .measured {
                    report.status = .empty
                    report.statusNoteES = "Sin elementos detectados"
                    report.statusNoteEN = "No items detected"
                } else if hadPartial || report.status == .partial {
                    report.statusNoteES = report.statusNoteES.replacingOccurrences(of: "(\(previousCount) elementos", with: "(\(b.itemCount) elementos")
                    report.statusNoteEN = report.statusNoteEN.replacingOccurrences(of: "(\(previousCount) items", with: "(\(b.itemCount) items")
                    if report.status != .partial || report.statusNoteES.isEmpty {
                        report.statusNoteES = "Resultados parciales (\(b.itemCount) elementos)"
                        report.statusNoteEN = "Partial results (\(b.itemCount) items)"
                    }
                    report.status = .partial
                } else {
                    report.status = .measured
                    report.statusNoteES = "Medido (\(b.itemCount) elementos)"
                    report.statusNoteEN = "Measured (\(b.itemCount) items)"
                }
            }
            updated.append(report)
        }
        categories = updated
        if globalOverflow && !files.isEmpty && !errors.contains("Byte total exceeds representable limit") {
            errors.append("Byte total exceeds representable limit")
        }
        complete = finishedAt != nil && !cancelled && !isStale && errors.isEmpty && categories.allSatisfy {
            $0.status != .partial && $0.status != .pending && $0.status != .noAccess && $0.status != .scanning
        }
    }
}
public struct Preferences: Codable, Sendable {
    public var roots: [String] = []
    public var inventoryRoots: [String] = []
    public var protectedPaths: [String] = []
    public var notifications = false
    public var language = "system"
    public var appearance = "system"
    public var showMenuBarFreeSpace = false
    public var keptProcesses: [Int32] = []
    public init() {}

    enum CodingKeys: String, CodingKey {
        case roots, inventoryRoots, protectedPaths, notifications, language, appearance, showMenuBarFreeSpace, keptProcesses
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        roots = try c.decodeIfPresent([String].self, forKey: .roots) ?? []
        inventoryRoots = try c.decodeIfPresent([String].self, forKey: .inventoryRoots) ?? []
        protectedPaths = try c.decodeIfPresent([String].self, forKey: .protectedPaths) ?? []
        notifications = try c.decodeIfPresent(Bool.self, forKey: .notifications) ?? false
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? "system"
        appearance = try c.decodeIfPresent(String.self, forKey: .appearance) ?? "system"
        showMenuBarFreeSpace = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarFreeSpace) ?? false
        keptProcesses = try c.decodeIfPresent([Int32].self, forKey: .keptProcesses) ?? []
    }
}
public struct ActivityEntry: Codable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var date = Date()
    public let message: String
    public init(_ message: String) { self.message = message }
}
public struct JournalEntry: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var date = Date()
    public let operation: String
    public let originalPath: String
    public let size: Int64
    public var allocatedBytes: Int64?
    public let identity: FileIdentity
    public var trashPath: String?
    public var status: String
    public var error: String?
    public var restoredAt: Date?
    public var freeSpaceBefore: Int64?
    public var freeSpaceAfter: Int64?
    public var domain: String?
    public var mechanism: String?
    public var restorable: Bool?
    public var planID: String?
    public var outcomeKind: String?
    public var summaryTitle: String?
    public var summaryTitleES: String?
    public var detailNote: String?
    public var detailNoteES: String?
    public var completedCount: Int?
    public var skippedOrFailedCount: Int?

    public init(
        id: String = UUID().uuidString,
        date: Date = Date(),
        operation: String,
        originalPath: String,
        size: Int64,
        allocatedBytes: Int64? = nil,
        identity: FileIdentity = FileIdentity(device: 0, inode: 0, size: 0, modified: 0, changed: 0),
        trashPath: String? = nil,
        status: String,
        error: String? = nil,
        restoredAt: Date? = nil,
        freeSpaceBefore: Int64? = nil,
        freeSpaceAfter: Int64? = nil,
        domain: String? = nil,
        mechanism: String? = nil,
        restorable: Bool? = nil,
        planID: String? = nil,
        outcomeKind: String? = nil,
        summaryTitle: String? = nil,
        summaryTitleES: String? = nil,
        detailNote: String? = nil,
        detailNoteES: String? = nil,
        completedCount: Int? = nil,
        skippedOrFailedCount: Int? = nil
    ) {
        self.id = id
        self.date = date
        self.operation = operation
        self.originalPath = originalPath
        self.size = size
        self.allocatedBytes = allocatedBytes
        self.identity = identity
        self.trashPath = trashPath
        self.status = status
        self.error = error
        self.restoredAt = restoredAt
        self.freeSpaceBefore = freeSpaceBefore
        self.freeSpaceAfter = freeSpaceAfter
        self.domain = domain
        self.mechanism = mechanism
        self.restorable = restorable
        self.planID = planID
        self.outcomeKind = outcomeKind
        self.summaryTitle = summaryTitle
        self.summaryTitleES = summaryTitleES
        self.detailNote = detailNote
        self.detailNoteES = detailNoteES
        self.completedCount = completedCount
        self.skippedOrFailedCount = skippedOrFailedCount
    }

    public var freeSpaceDelta: Int64? {
        guard let before = freeSpaceBefore, let after = freeSpaceAfter else { return nil }
        return after - before
    }
}
public struct AgentInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let executable: String?
    public let authentication: String
    public let executionEnabled: Bool
}
public struct AgentConclusion: Codable, Sendable {
    public let fileID: String
    public let measuredSize: Int64
    public let explanation: String
    public let confidence: Double
    public init(fileID: String, measuredSize: Int64, explanation: String, confidence: Double) {
        self.fileID = fileID; self.measuredSize = measuredSize
        self.explanation = explanation; self.confidence = confidence
    }
}
public enum AgentValidator {
    public static func validate(_ conclusions: [AgentConclusion], index: [IndexedFile]) throws -> [AgentConclusion] {
        guard conclusions.count <= 100 else { throw BrisaError.invalid("At most 100 conclusions") }
        var byID: [String: IndexedFile] = [:]
        for file in index {
            guard byID.updateValue(file, forKey: file.id) == nil else {
                throw BrisaError.rejected("Duplicate indexed file identity; refresh the inventory")
            }
        }
        var seen = Set<String>()
        for c in conclusions {
            guard let file = byID[c.fileID], file.isReviewable, file.size == c.measuredSize,
                  c.confidence.isFinite, (0...1).contains(c.confidence),
                  !c.explanation.isEmpty, c.explanation.utf8.count <= 2000,
                  !c.explanation.unicodeScalars.contains(where: { $0.value < 32 && $0 != "\n" }),
                  seen.insert(c.fileID).inserted else {
                throw BrisaError.rejected("Conclusion is not bound to an eligible measured file")
            }
        }
        return conclusions
    }
}

public enum Formatting {
    private static let formatterLock = NSLock()
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    public static func bytes(_ bytes: Int64) -> String {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        return byteFormatter.string(fromByteCount: bytes)
    }

    /// Whole decimal GB for menu-bar display to keep bar width steady between sub-GB fluctuations.
    public static func menuBarFreeGigabytes(_ freeBytes: Int64?) -> String? {
        guard let freeBytes, freeBytes >= 0 else { return nil }
        let gigabytes = freeBytes / 1_000_000_000
        return gigabytes > 0 ? "\(gigabytes) GB" : "< 1 GB"
    }
}

public enum ByteTotals {
    /// Byte counters saturate rather than trapping; aggregate coverage must remain partial on overflow.
    public static func adding(_ a: Int64, _ b: Int64) -> Int64 {
        let sum = a.addingReportingOverflow(b)
        return sum.overflow ? Int64.max : sum.partialValue
    }

    /// Invalid/overflowing external capacities stay unknown instead of crashing or wrapping.
    public static func knownSum(_ values: [Int64]) -> Int64? {
        guard !values.isEmpty else { return nil }
        var total: Int64 = 0
        for value in values {
            guard value >= 0 else { return nil }
            let next = total.addingReportingOverflow(value)
            guard !next.overflow else { return nil }
            total = next.partialValue
        }
        return total
    }
}
