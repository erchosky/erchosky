import XCTest
import Darwin
@testable import BrisaCore

final class SafetyTests: XCTestCase {
    func testPOSIXCanonicalSystemLocationAvoidsVarAlias() throws {
        let canonical = try Paths.systemLocation(NSTemporaryDirectory())
        XCTAssertNoThrow(try SafetyPolicy.rejectSymlinks(canonical))
        XCTAssertEqual(Paths.normalized("/private/var/a/../b"), "/private/var/b")
    }
    func testInvisibleAndMultilineNamesCannotSpoofReview() throws {
        let f = try Fixture()
        for name in ["first\nsecond.cache", "\u{202e}secret.cache", "\u{200b}hidden.cache"] {
            let url = try f.file(name)
            XCTAssertThrowsError(try f.policy().inspect(url.path))
        }
    }
    func testProtectionIsCaseConservative() throws {
        let f = try Fixture(), url = try f.file("kept/file.cache")
        let policy = try f.policy(protected: [f.root.appendingPathComponent("KEPT").path])
        XCTAssertThrowsError(try policy.inspect(url.path))
    }
    func testUnwritableFileIsRejected() throws {
        let f = try Fixture(), url = try f.file()
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: url.path)
        XCTAssertThrowsError(try f.policy().inspect(url.path))
    }
    func testOldCacheIsMeasuredAndClassified() throws {
        let f = try Fixture(), url = try f.file()
        let file = try f.policy().inspect(url.path)
        XCTAssertTrue(file.eligible); XCTAssertEqual(file.size, 1024)
        XCTAssertEqual(file.category, .cache); XCTAssertEqual(file.confidence, "medium")
        XCTAssertGreaterThanOrEqual(file.allocatedBytes, 0)
    }
    func testRecentCacheIsRetained() throws {
        let f = try Fixture(), url = try f.file(days: 2)
        let file = try f.policy().inspect(url.path)
        XCTAssertFalse(file.eligible); XCTAssertEqual(file.reason, "recent_file")
    }
    func testUnknownExtensionIsInventoryOnly() throws {
        let f = try Fixture(), url = try f.file("photo.jpg")
        let file = try f.policy().inspect(url.path)
        XCTAssertFalse(file.eligible); XCTAssertEqual(file.category, .other)
    }
    func testLogThresholdIsThirtyDays() throws {
        let f = try Fixture(), logs = f.home.appendingPathComponent("Library/Logs")
        let recent = try f.file("recent.log", days: 20, directory: logs)
        let old = try f.file("old.log", days: 31, directory: logs)
        let policy = try SafetyPolicy(roots: [logs.path], home: f.home.path)
        XCTAssertFalse(try policy.inspect(recent.path).eligible)
        XCTAssertTrue(try policy.inspect(old.path).eligible)
    }
    func testUserProtectionIncludesDescendantsButNotPrefixSiblings() throws {
        let f = try Fixture(), a = try f.file("kept/file.cache"), b = try f.file("kept-too/file.cache")
        let policy = try f.policy(protected: [f.root.appendingPathComponent("kept").path])
        XCTAssertThrowsError(try policy.inspect(a.path)); XCTAssertTrue(try policy.inspect(b.path).eligible)
    }
    func testSensitiveNamesAreRejected() throws {
        let f = try Fixture()
        for name in [".env", ".env.production", "auth-token.cache", "credentials/a.cache", "sessions/a.cache", "private.pem", "keychains/a.cache"] {
            let url = try f.file(name)
            XCTAssertThrowsError(try f.policy().inspect(url.path), name)
        }
    }
    func testProtectedRootsCannotBeIndexed() throws {
        let f = try Fixture()
        for path in ["Documents", "Downloads", ".ssh", "Pictures", "Library/Mail", "Library/Messages", "Library/Mobile Documents", "Library/CloudStorage", "Library/Keychains", ".codex", ".Trash"] {
            let url = f.home.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            XCTAssertThrowsError(try SafetyPolicy(roots: [url.path], home: f.home.path), path)
        }
    }
    func testRejectHomeRootAndOutsideRoot() throws {
        let f = try Fixture()
        XCTAssertThrowsError(try SafetyPolicy(roots: [f.home.path], home: f.home.path))
        XCTAssertThrowsError(try SafetyPolicy(roots: ["/"], home: f.home.path))
        let outside = try f.file(directory: f.home.appendingPathComponent("Elsewhere"))
        XCTAssertThrowsError(try f.policy().inspect(outside.path))
    }
    func testSymlinkLeafAndAncestorRejected() throws {
        let f = try Fixture(), original = try f.file(), link = f.root.appendingPathComponent("link.cache")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        XCTAssertThrowsError(try f.policy().inspect(link.path))
        let dirLink = f.home.appendingPathComponent("Alias")
        try FileManager.default.createSymbolicLink(at: dirLink, withDestinationURL: f.root)
        XCTAssertThrowsError(try SafetyPolicy(roots: [dirLink.path], home: f.home.path))
    }
    func testHardLinksAndDirectoriesRejected() throws {
        let f = try Fixture(), original = try f.file()
        try FileManager.default.linkItem(at: original, to: f.root.appendingPathComponent("linked.cache"))
        XCTAssertThrowsError(try f.policy().inspect(original.path))
        XCTAssertThrowsError(try f.policy().inspect(f.root.path))
    }
    func testTraversalAndNulRejected() throws {
        let f = try Fixture(); _ = try f.file()
        XCTAssertThrowsError(try f.policy().inspect(f.root.path + "/../test.brisa/old.cache"))
        XCTAssertThrowsError(try f.policy().inspect(f.root.path + "/old.cache\0"))
        XCTAssertThrowsError(try SafetyPolicy(roots: ["relative"], home: f.home.path))
    }
    func testRevalidationRejectsChangedFile() throws {
        let f = try Fixture(), url = try f.file(), policy = try f.policy(), file = try policy.inspect(url.path)
        try Data("changed".utf8).write(to: url)
        XCTAssertThrowsError(try policy.revalidate(file))
    }
    func testRevalidationRejectsSameSizeReplacement() throws {
        let f = try Fixture(), url = try f.file(), policy = try f.policy(), file = try policy.inspect(url.path)
        try FileManager.default.removeItem(at: url); _ = try f.file()
        XCTAssertThrowsError(try policy.revalidate(file))
    }
    func testRevalidationRejectsSymlinkSubstitution() throws {
        let f = try Fixture(), url = try f.file(), policy = try f.policy(), file = try policy.inspect(url.path)
        let target = try f.file("other.cache")
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        XCTAssertThrowsError(try policy.revalidate(file))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }
    func testGitWorkingCopyCannotBecomeCache() throws {
        let f = try Fixture(), url = try f.file()
        try FileManager.default.createDirectory(at: f.root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        XCTAssertThrowsError(try f.policy().inspect(url.path))
    }
    func testWorldWritableAncestorRejected() throws {
        let f = try Fixture(), url = try f.file()
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: f.root.path)
        XCTAssertThrowsError(try SafetyPolicy(roots: [f.root.path], home: f.home.path))
        XCTAssertThrowsError(try SafetyPolicy.rejectSymlinks(url.path))
    }
    func testCancellationAndBudgetsMarkPartialResults() throws {
        let f = try Fixture(); _ = try f.file("a.txt"); _ = try f.file("b.txt")
        let cancelled = CancellationFlag(); cancelled.cancel()
        let a = Indexer.scan(policy: try f.policy(), cancellation: cancelled)
        XCTAssertTrue(a.cancelled); XCTAssertFalse(a.complete)
        let b = Indexer.scan(policy: try f.policy(), maxEntries: 1)
        XCTAssertFalse(b.complete); XCTAssertEqual(b.examined, 1)
        XCTAssertTrue(b.errors.contains { $0.contains("budget") })
    }
    func testIndexExcludesProtectedAndDeduplicatesOverlappingRoots() throws {
        let f = try Fixture(); _ = try f.file("a.txt"); _ = try f.file("sessions/hidden.txt")
        let policy = try SafetyPolicy(roots: [f.root.path, f.root.path], home: f.home.path)
        let scan = Indexer.scan(policy: policy)
        XCTAssertEqual(scan.files.count, 1); XCTAssertTrue(scan.complete)
    }
}
