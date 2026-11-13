import Foundation
import Darwin

public protocol TrashMoving: Sendable {
    func move(_ url: URL) throws -> URL?
}
public struct SystemTrashMover: TrashMoving {
    public init() {}
    public func move(_ url: URL) throws -> URL? {
        var destination: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
        return destination as URL?
    }
}

/// Confirmation belongs to the app. The only caller in shipping executables is its main-actor coordinator.
/// This module has no agent API and never interprets generated text as an operation.
public final class TrashOperations: @unchecked Sendable {
    private let journal: Journal
    private let lock = NSLock()
    private let mover: TrashMoving
    private let requireIdle: (IndexedFile) throws -> Void
    public init(journal: Journal, mover: any TrashMoving = SystemTrashMover()) {
        self.journal = journal; self.mover = mover; requireIdle = ProcessInspector.requireIdle
    }
    // Test-only injection is internal; shipping executables can only use idle checks.
    init(journal: Journal, mover: TrashMoving, requireIdle: @escaping (IndexedFile) throws -> Void = ProcessInspector.requireIdle) {
        self.journal = journal; self.mover = mover; self.requireIdle = requireIdle
    }
    private static func currentFreeSpace(for path: String) -> Int64? {
        if let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeAvailableCapacityKey]),
           let free = values.volumeAvailableCapacity {
            return Int64(free)
        }
        return nil
    }
    public func moveToTrash(_ files: [IndexedFile], policy: SafetyPolicy, cancellation: CancellationFlag) throws -> [JournalEntry] {
        guard lock.try() else { throw BrisaError.rejected("Another operation is running") }
        defer { lock.unlock() }
        guard !files.isEmpty, files.count <= 100 else { throw BrisaError.invalid("Select 1–100 items") }
        guard Set(files.map(\.path)).count == files.count else { throw BrisaError.invalid("Duplicate selection") }
        _ = try journal.entries() // Fail closed before changing files if the journal is corrupt.
        var results: [JournalEntry] = []
        for file in files {
            if cancellation.isCancelled { break }
            let freeBefore = Self.currentFreeSpace(for: policy.home)
            var entry = JournalEntry(
                operation: "trash",
                originalPath: file.path,
                size: file.size,
                allocatedBytes: file.allocatedBytes,
                identity: file.identity,
                status: "intent",
                freeSpaceBefore: freeBefore,
                domain: OperationDomain.cacheInventory.rawValue,
                mechanism: OperationMechanism.trash.rawValue,
                restorable: false
            )
            do {
                _ = try policy.revalidate(file)
                try requireIdle(file)
                let fd = Darwin.open(file.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
                guard fd >= 0 else { throw BrisaError.rejected("Cannot open file safely") }
                defer { close(fd) }
                var st = stat()
                guard fstat(fd, &st) == 0, SafetyPolicy.identity(st) == file.identity,
                      flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw BrisaError.rejected("File changed or is locked") }
                defer { _ = flock(fd, LOCK_UN) }
                try journal.append(entry)
                _ = try policy.revalidate(file)
                // The held descriptor is our own. Recheck other readers immediately before the move.
                guard try ProcessInspector.openPIDs(file.path).allSatisfy({ $0 == getpid() }) else {
                    throw BrisaError.rejected("File opened during confirmation")
                }
                let destination = try mover.move(URL(fileURLWithPath: file.path))
                entry.trashPath = destination?.path; entry.status = "trashed"
                entry.restorable = true
                entry.outcomeKind = OperationOutcomeStatus.completed.rawValue
                entry.freeSpaceAfter = Self.currentFreeSpace(for: policy.home)
                // If recording the result fails, keep the intent on disk and stop the batch.
                do { try journal.append(entry) }
                catch { throw BrisaError.io("Item moved to Trash but journal result could not be saved; stop and inspect Trash") }
            } catch {
                if entry.status == "trashed" { throw error }
                entry.status = "rejected"; entry.error = error.localizedDescription
                entry.outcomeKind = OperationOutcomeStatus.rejected.rawValue
                entry.restorable = false
                entry.freeSpaceAfter = Self.currentFreeSpace(for: policy.home)
                try journal.append(entry)
            }
            results.append(entry)
        }
        return results
    }
    public func restore(_ id: String, home: String = NSHomeDirectory(), protectedPaths: [String] = []) throws -> JournalEntry {
        guard lock.try() else { throw BrisaError.rejected("Another operation is running") }
        defer { lock.unlock() }
        guard var entry = try journal.entries().first(where: { $0.id == id }), entry.status == "trashed",
              let path = entry.trashPath, SafetyPolicy.within(path, Paths.normalized(home) + "/.Trash") else {
            throw BrisaError.rejected("No restorable item in the user's Trash")
        }
        // Exclude symlinked parents; the destination itself must be absent. Never overwrite a recreated file.
        try SafetyPolicy.rejectSymlinks(path)
        let destination = URL(fileURLWithPath: entry.originalPath)
        try SafetyPolicy.rejectSymlinks(destination.deletingLastPathComponent().path)
        let policy = try SafetyPolicy(roots: [destination.deletingLastPathComponent().path],
                                      protectedPaths: protectedPaths, home: home)
        guard policy.exclusion(entry.originalPath) == nil else { throw BrisaError.rejected("Original location is now protected") }
        var st = stat()
        guard lstat(entry.originalPath, &st) != 0, errno == ENOENT,
              lstat(path, &st) == 0, st.st_uid == getuid(), st.st_mode & S_IFMT == S_IFREG,
              st.st_nlink == 1, UInt64(UInt32(bitPattern: st.st_dev)) == entry.identity.device,
              st.st_ino == entry.identity.inode, st.st_size == entry.size,
              SafetyPolicy.identity(st).modified == entry.identity.modified,
              try ProcessInspector.openPIDs(path).isEmpty else {
            throw BrisaError.rejected("Trash item changed, is open, or destination exists")
        }
        entry.status = "restore_intent"; try journal.append(entry)
        // RENAME_EXCL is an atomic no-overwrite move on macOS.
        guard renamex_np(path, entry.originalPath, UInt32(RENAME_EXCL)) == 0 else {
            entry.status = "trashed"; entry.error = "Restore failed (errno \(errno))"; try journal.append(entry)
            throw BrisaError.io("Cannot restore; original was not overwritten")
        }
        entry.status = "restored"; entry.restoredAt = Date(); entry.error = nil; try journal.append(entry)
        return entry
    }
}
