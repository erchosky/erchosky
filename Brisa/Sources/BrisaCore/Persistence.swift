import Foundation
import CryptoKit
import Darwin

public final class PrivateStore: @unchecked Sendable {
    public let directory: URL
    private let lock = NSRecursiveLock()
    private let encoder: JSONEncoder
    public init(directory: URL? = nil) throws {
        self.directory = directory ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Brisa", isDirectory: true)
        encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .millisecondsSince1970
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try SafetyPolicy.rejectSymlinks(self.directory.path)
        var st = stat()
        guard lstat(self.directory.path, &st) == 0, st.st_uid == getuid(), st.st_mode & 0o077 == 0 else {
            throw BrisaError.rejected("State directory must be owned by you with mode 0700")
        }
    }
    public func read<T: Decodable>(_ name: String, as type: T.Type) throws -> T? {
        lock.lock(); defer { lock.unlock() }
        let url = try file(name)
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd < 0 { if errno == ENOENT { return nil }; throw BrisaError.io("Cannot read state") }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_uid == getuid(), st.st_mode & S_IFMT == S_IFREG,
              st.st_nlink == 1, st.st_mode & 0o077 == 0, st.st_size >= 0, st.st_size <= 32 * 1024 * 1024 else {
            throw BrisaError.rejected("Unsafe or oversized state file")
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let data = try handle.read(upToCount: 32 * 1024 * 1024 + 1) ?? Data()
        guard data.count <= 32 * 1024 * 1024 else { throw BrisaError.rejected("State grew beyond the read budget") }
        return try decoder.decode(type, from: data)
    }
    public func write<T: Encodable>(_ name: String, value: T) throws {
        lock.lock(); defer { lock.unlock() }
        let url = try file(name)
        let temporary = directory.appendingPathComponent(UUID().uuidString + ".tmp")
        let data = try encoder.encode(value)
        guard data.count <= 32 * 1024 * 1024 else { throw BrisaError.io("State budget exceeded") }
        let fd = Darwin.open(temporary.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw BrisaError.io("Cannot create private state") }
        defer { close(fd); unlink(temporary.path) }
        try FileHandle(fileDescriptor: fd, closeOnDealloc: false).write(contentsOf: data)
        guard fsync(fd) == 0, rename(temporary.path, url.path) == 0 else { throw BrisaError.io("Cannot commit state") }
        let dirFD = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY)
        if dirFD >= 0 { _ = fsync(dirFD); close(dirFD) }
    }
    private func file(_ name: String) throws -> URL {
        guard !name.isEmpty, !name.contains("/"), !name.contains(".."), !name.contains("\0") else { throw BrisaError.invalid("Invalid state name") }
        return directory.appendingPathComponent(name)
    }
}

private struct JournalRecord: Codable {
    let previous: String
    let payload: Data
    let hash: String
}
public final class Journal: @unchecked Sendable {
    private let store: PrivateStore
    private let lock = NSLock()
    public init(store: PrivateStore) { self.store = store }
    public func entries() throws -> [JournalEntry] {
        lock.lock(); defer { lock.unlock() }; return try read().1
    }
    public func append(_ entry: JournalEntry) throws {
        lock.lock(); defer { lock.unlock() }
        var records = try read().0
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .millisecondsSince1970
        let payload = try encoder.encode(entry), previous = records.last?.hash ?? "brisa-journal-v1"
        let hash = Self.digest(previous, payload)
        records.append(JournalRecord(previous: previous, payload: payload, hash: hash))
        try store.write("journal.json", value: records)
    }
    private func read() throws -> ([JournalRecord], [JournalEntry]) {
        let records = try store.read("journal.json", as: [JournalRecord].self) ?? []
        var previous = "brisa-journal-v1", byID: [String: JournalEntry] = [:]
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        for record in records {
            guard record.previous == previous, record.hash == Self.digest(previous, record.payload) else {
                throw BrisaError.rejected("Journal integrity verification failed")
            }
            let entry = try decoder.decode(JournalEntry.self, from: record.payload)
            byID[entry.id] = entry; previous = record.hash
        }
        return (records, byID.values.sorted { $0.date > $1.date })
    }
    private static func digest(_ previous: String, _ payload: Data) -> String {
        SHA256.hash(data: Data(previous.utf8) + payload).map { String(format: "%02x", $0) }.joined()
    }
}
