import Foundation

public final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    public init() {}
    public func cancel() { lock.lock(); value = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

public enum Indexer {
    public static func scan(policy: SafetyPolicy, cancellation: CancellationFlag = CancellationFlag(),
                            maxEntries: Int = 50_000, timeLimit: TimeInterval = 20) -> ScanResult {
        var result = ScanResult()
        result.roots = policy.roots
        let deadline = Date().addingTimeInterval(timeLimit)
        var seen = Set<String>()
        outer: for root in policy.roots {
            guard let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { url, _ in
                    if result.errors.count < 30 { result.errors.append("Unreadable: \(url.path)") }; return true
                }) else { result.errors.append("Unreadable root: \(root)"); continue }
            for case let url as URL in enumerator {
                if cancellation.isCancelled || Date() >= deadline || result.examined >= maxEntries {
                    result.cancelled = cancellation.isCancelled
                    if !result.cancelled { result.errors.append("Scan budget reached; results are partial") }
                    break outer
                }
                result.examined += 1
                if result.examined % 200 == 0 { Thread.sleep(forTimeInterval: 0.005) }
                if policy.exclusion(url.path) != nil { enumerator.skipDescendants(); result.skipped += 1; continue }
                do {
                    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    if values.isSymbolicLink == true { enumerator.skipDescendants(); result.skipped += 1; continue }
                    if values.isDirectory == true {
                        if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) { enumerator.skipDescendants(); result.skipped += 1 }
                        continue
                    }
                    var file = try policy.inspect(url.path)
                    if file.eligible {
                        do { try ProcessInspector.requireIdle(file) }
                        catch { file.eligible = false; file.reason = "open_or_uncertain"; file.confidence = "none" }
                    }
                    if seen.insert(file.path).inserted { result.files.append(file) }
                } catch { result.skipped += 1 }
            }
        }
        result.complete = !result.cancelled && result.errors.isEmpty
        result.finishedAt = Date()
        result.files.sort { $0.size > $1.size }
        return result
    }
}
