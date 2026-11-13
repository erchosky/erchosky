import XCTest
import Darwin
@testable import BrisaCore

final class OperationTests: XCTestCase {
    func testControlledMoveAndRestoreWithRealJournal() throws {
        let f = try Fixture(), url = try f.file(), policy = try f.policy(), file = try policy.inspect(url.path)
        let journal = Journal(store: try f.store()), ops = try f.operations(journal: journal)
        let result = try ops.moveToTrash([file], policy: policy, cancellation: CancellationFlag())
        XCTAssertEqual(result.first?.status, "trashed"); XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let restored = try ops.restore(result[0].id, home: f.home.path)
        XCTAssertEqual(restored.status, "restored"); XCTAssertEqual(try Data(contentsOf: url).count, 1024)
        XCTAssertEqual(try journal.entries().count, 1)
    }
    func testOpenFileBetweenScanAndActionIsRetained() throws {
        let f = try Fixture(), url = try f.file(), policy = try f.policy(), file = try policy.inspect(url.path)
        let journal = Journal(store: try f.store()), ops = try f.operations(journal: journal)
        let fd = Darwin.open(url.path, O_RDONLY); XCTAssertGreaterThanOrEqual(fd, 0); defer { close(fd) }
        XCTAssertTrue(try ProcessInspector.openPIDs(url.path).contains(getpid()))
        let result = try ops.moveToTrash([file], policy: policy, cancellation: CancellationFlag())
        XCTAssertEqual(result[0].status, "rejected"); XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
    func testRecentlyModifiedParentIsRetained() throws {
        let f = try Fixture(), url = try f.file(), policy = try f.policy(), file = try policy.inspect(url.path)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: f.root.path)
        let ops = try f.operations(journal: Journal(store: f.store()))
        let result = try ops.moveToTrash([file], policy: policy, cancellation: CancellationFlag())
        XCTAssertEqual(result[0].status, "rejected"); XCTAssertTrue(result[0].error?.contains("24 hours") == true)
    }
    func testFileChangedAfterAnalysisIsRetained() throws {
        let f = try Fixture(), url = try f.file(), policy = try f.policy(), file = try policy.inspect(url.path)
        try Data("new".utf8).write(to: url)
        let ops = try f.operations(journal: Journal(store: f.store()))
        let result = try ops.moveToTrash([file], policy: policy, cancellation: CancellationFlag())
        XCTAssertEqual(result[0].status, "rejected"); XCTAssertEqual(try Data(contentsOf: url), Data("new".utf8))
    }
    func testRestoreNeverOverwritesNewFile() throws {
        let f = try Fixture(), url = try f.file(), policy = try f.policy(), file = try policy.inspect(url.path)
        let ops = try f.operations(journal: Journal(store: f.store()))
        let moved = try ops.moveToTrash([file], policy: policy, cancellation: CancellationFlag())
        try Data("personal replacement".utf8).write(to: url)
        XCTAssertThrowsError(try ops.restore(moved[0].id, home: f.home.path))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "personal replacement")
    }
    func testRestoreHonorsProtectionsAddedAfterTrash() throws {
        for protectParent in [false, true] {
            let f = try Fixture(), url = try f.file(), policy = try f.policy()
            let journal = Journal(store: try f.store()), ops = try f.operations(journal: journal)
            let moved = try ops.moveToTrash([policy.inspect(url.path)], policy: policy, cancellation: CancellationFlag())
            let entry = try XCTUnwrap(moved.first)
            XCTAssertEqual(entry.status, "trashed")
            let protection = protectParent ? f.root.path : url.path

            XCTAssertThrowsError(try ops.restore(entry.id, home: f.home.path, protectedPaths: [protection]))
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(entry.trashPath)))
            XCTAssertEqual(try journal.entries().first?.status, "trashed")

            // Removing the new protection permits the same item to be restored.
            XCTAssertEqual(try ops.restore(entry.id, home: f.home.path).status, "restored")
            XCTAssertEqual(try Data(contentsOf: url).count, 1024)
        }
    }
    func testRestoreProtectionDoesNotBlockPrefixSibling() throws {
        let f = try Fixture(), url = try f.file("kept-too/old.cache"), policy = try f.policy()
        let ops = try f.operations(journal: Journal(store: f.store()))
        let moved = try ops.moveToTrash([policy.inspect(url.path)], policy: policy, cancellation: CancellationFlag())
        XCTAssertEqual(try ops.restore(moved[0].id, home: f.home.path,
                                      protectedPaths: [f.root.appendingPathComponent("kept").path]).status, "restored")
    }
    func testMissingTrashItemCannotRestore() throws {
        let f = try Fixture(), url = try f.file(), policy = try f.policy(), file = try policy.inspect(url.path)
        let ops = try f.operations(journal: Journal(store: f.store()))
        let moved = try ops.moveToTrash([file], policy: policy, cancellation: CancellationFlag())
        try FileManager.default.removeItem(atPath: moved[0].trashPath!)
        XCTAssertThrowsError(try ops.restore(moved[0].id, home: f.home.path))
    }
    func testCancelledBatchDoesNotMoveFiles() throws {
        let f = try Fixture(), url = try f.file(), policy = try f.policy(), file = try policy.inspect(url.path)
        let ops = try f.operations(journal: Journal(store: f.store())), flag = CancellationFlag(); flag.cancel()
        XCTAssertTrue(try ops.moveToTrash([file], policy: policy, cancellation: flag).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
    func testDuplicateSelectionsRejected() throws {
        let f = try Fixture(), url = try f.file(), policy = try f.policy(), file = try policy.inspect(url.path)
        let ops = try f.operations(journal: Journal(store: f.store()))
        XCTAssertThrowsError(try ops.moveToTrash([file, file], policy: policy, cancellation: CancellationFlag()))
    }
    func testAgentSessionStopsCleanup() throws {
        let f = try Fixture(), url = try f.file(), file = try f.policy().inspect(url.path)
        let agent = ProcessInfoEntry(id: 123, executable: "/usr/local/bin/codex", isAgent: true)
        XCTAssertThrowsError(try ProcessInspector.requireIdle(file, processes: [agent]))
    }
    func testAdvisoryLockIsRespected() throws {
        let f = try Fixture(), url = try f.file(), policy = try f.policy(), file = try policy.inspect(url.path)
        let fd = Darwin.open(url.path, O_RDONLY); defer { close(fd) }
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        let ops = try f.operations(journal: Journal(store: f.store()))
        let result = try ops.moveToTrash([file], policy: policy, cancellation: CancellationFlag())
        XCTAssertEqual(result[0].status, "rejected")
    }
}
