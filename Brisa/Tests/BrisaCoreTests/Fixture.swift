import Foundation
import Darwin
@testable import BrisaCore

final class Fixture {
    let home: URL
    let root: URL
    init() throws {
        home = URL(fileURLWithPath: try Paths.systemLocation(NSTemporaryDirectory())).appendingPathComponent("BrisaT-" + UUID().uuidString.prefix(12), isDirectory: true)
        root = home.appendingPathComponent("Library/Caches/test.brisa", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    func file(_ name: String = "old.cache", days: Double = 45, size: Int = 1024, directory: URL? = nil) throws -> URL {
        let url = (directory ?? root).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data(repeating: 65, count: size).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-days * 86400)], ofItemAtPath: url.path)
        try ageDirectories(url.deletingLastPathComponent())
        return url
    }
    func ageDirectories(_ start: URL? = nil) throws {
        var url = start ?? root
        while SafetyPolicy.within(url.path, home.path) {
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-45 * 86400)], ofItemAtPath: url.path)
            if url == home { break }; url.deleteLastPathComponent()
        }
    }
    func policy(protected: [String] = []) throws -> SafetyPolicy {
        try SafetyPolicy(roots: [root.path], protectedPaths: protected, home: home.path)
    }
    func store() throws -> PrivateStore { try PrivateStore(directory: home.appendingPathComponent("State")) }
    func operations(journal: Journal) throws -> TrashOperations {
        let trash = home.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return TrashOperations(journal: journal, mover: ControlledTrash(directory: trash), requireIdle: {
            // Controlled fixture has no agent workspace. Real lsof and parent activity checks remain enabled.
            try ProcessInspector.requireIdle($0, processes: [])
        })
    }
    deinit { try? FileManager.default.removeItem(at: home) }
}
struct ControlledTrash: TrashMoving {
    let directory: URL
    func move(_ url: URL) throws -> URL? {
        let target = directory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }
}
