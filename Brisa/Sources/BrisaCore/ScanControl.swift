import Foundation

/// Coverage can be partial without a timeout (for example, a directory/depth cap).
public final class ScanCoverage: @unchecked Sendable {
    private let lock = NSLock()
    private var notes = Set<String>()
    public init() {}
    public func record(_ reason: String) { lock.lock(); defer { lock.unlock() }; notes.insert(reason) }
    public var reasons: [String] { lock.lock(); defer { lock.unlock() }; return notes.sorted() }
}

/// Shared cancellation and wall-clock deadline across discovery, measurement and subprocesses.
/// A timeout is not a user cancellation: callers can report the two causes separately.
public struct ScanControl: Sendable {
    public let cancellation: CancellationFlag
    public let deadline: Date
    public let coverage: ScanCoverage

    public init(cancellation: CancellationFlag = CancellationFlag(), deadline: Date = .distantFuture,
                coverage: ScanCoverage = ScanCoverage()) {
        self.cancellation = cancellation
        self.deadline = deadline
        self.coverage = coverage
    }

    public var shouldStop: Bool { cancellation.isCancelled || Date() >= deadline }
    public var isPartial: Bool { shouldStop || !coverage.reasons.isEmpty }
    public var remainingTime: TimeInterval { max(0, deadline.timeIntervalSinceNow) }
}

/// Thread-safe box for transferring values across bounded concurrent worker closures.
final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ initial: Value) {
        self.storage = initial
    }

    func set(_ value: Value) {
        lock.withLock { storage = value }
    }

    func get() -> Value {
        lock.withLock { storage }
    }
}

/// Bounded worker pool preserving input order while honoring scan cancellation.
enum BoundedConcurrency {
    static func mapOrdered<Input: Sendable, Output: Sendable>(
        _ items: [Input],
        maxConcurrent: Int = 4,
        control: ScanControl = ScanControl(),
        transform: @escaping @Sendable (Input) -> Output
    ) -> [Output?] {
        guard !items.isEmpty else { return [] }
        if items.count == 1 || maxConcurrent <= 1 {
            guard !control.shouldStop else { return [] }
            return items.compactMap { item in
                guard !control.shouldStop else { return nil }
                return transform(item)
            }
        }

        let slots = LockedBox<[Output?]>(Array(repeating: nil, count: items.count))
        let writeLock = NSLock()
        let group = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)
        let semaphore = DispatchSemaphore(value: max(1, min(maxConcurrent, items.count)))

        for (idx, item) in items.enumerated() {
            if control.shouldStop { break }
            group.enter()
            queue.async {
                semaphore.wait()
                defer { semaphore.signal(); group.leave() }
                guard !control.shouldStop else { return }
                let result = transform(item)
                writeLock.withLock {
                    var copy = slots.get()
                    copy[idx] = result
                    slots.set(copy)
                }
            }
        }
        group.wait()
        return slots.get()
    }
}
