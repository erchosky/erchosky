import Foundation
import Darwin

public struct SafetyPolicy: Sendable {
    public let home: String
    public let roots: [String]
    public let protectedPaths: [String]
    public let minimumAge: TimeInterval
    public init(roots: [String], protectedPaths: [String] = [], home: String = NSHomeDirectory(), minimumAge: TimeInterval = 7 * 86400) throws {
        let canonicalHome = Paths.normalized(home)
        self.home = canonicalHome
        self.minimumAge = max(minimumAge, 7 * 86400)
        self.protectedPaths = protectedPaths.map(Paths.normalized)
        self.roots = try roots.map { path in
            guard path.hasPrefix("/"), !path.contains("\0"), path.utf8.count < 4096 else {
                throw BrisaError.invalid("Absolute root required")
            }
            let url = URL(fileURLWithPath: Paths.normalized(path))
            guard ["Library/Caches", "Library/Logs"].contains(where: {
                Self.within(url.path, canonicalHome + "/" + $0)
            }) else { throw BrisaError.rejected("Cleanup roots must be inside ~/Library/Caches or ~/Library/Logs") }
            guard url.path != "/", url.path != canonicalHome, Self.within(url.path, canonicalHome) else {
                throw BrisaError.rejected("Choose a directory inside your home, not the home directory itself")
            }
            try Self.rejectSymlinks(url.path)
            var st = stat()
            guard lstat(url.path, &st) == 0, st.st_mode & S_IFMT == S_IFDIR,
                  st.st_uid == getuid() else { throw BrisaError.rejected("Root is not an owned directory") }
            return url.path
        }
        for root in self.roots {
            if exclusion(root) != nil { throw BrisaError.rejected("Protected root: \(root)") }
        }
    }
    public static func within(_ path: String, _ parent: String) -> Bool {
        if parent == "/" { return path.hasPrefix("/") }
        return path == parent || path.hasPrefix(parent + "/")
    }
    public func exclusion(_ path: String) -> String? {
        let protected = [".ssh", ".gnupg", ".aws", ".azure", ".kube", ".codex", ".claude", ".gemini", ".Trash",
            "Pictures", "Photos", "Music", "Movies", "Desktop", "Documents", "Downloads",
            "Library/Keychains", "Library/Mail", "Library/Messages", "Library/Mobile Documents",
            "Library/CloudStorage", "Library/Accounts", "Library/Containers", "Library/Group Containers",
            "Library/Application Support", "Library/Preferences", "Library/IdentityServices"]
        // Overprotect case-sensitive volumes too; case aliases must never bypass an exclusion.
        if protected.contains(where: { Self.within(path.lowercased(), (home + "/" + $0).lowercased()) }) { return "protected_location" }
        if protectedPaths.contains(where: { Self.within(path.lowercased(), $0.lowercased()) }) { return "user_protected" }
        let parts = path.split(separator: "/").map { $0.lowercased() }
        let sensitive: Set<String> = [".git", ".ssh", ".gnupg", "keychains", "credentials", "secrets", "sessions", "session", "cookies", "mail", "messages", ".trash", "icloud", "cloudstorage"]
        if parts.contains(where: { sensitive.contains($0) || $0.hasPrefix(".env") || $0.hasSuffix(".photoslibrary") || $0.contains("credential") || $0.contains("token") || $0.hasSuffix(".key") || $0.hasSuffix(".pem") || $0.hasSuffix(".sqlite") || $0.hasSuffix(".db") }) { return "sensitive_name" }
        if parts.contains(where: { $0.hasPrefix(".") }) { return "hidden_location" }
        return nil
    }
    public static func rejectSymlinks(_ path: String) throws {
        var current = ""
        for component in path.split(separator: "/") {
            current += "/" + component
            var st = stat()
            guard lstat(current, &st) == 0 else { throw BrisaError.rejected("Path component unavailable") }
            guard st.st_mode & S_IFMT != S_IFLNK else { throw BrisaError.rejected("Symbolic link in path") }
            guard st.st_uid == getuid() || st.st_uid == 0 else { throw BrisaError.rejected("Untrusted path owner") }
            guard st.st_mode & S_IWOTH == 0 else { throw BrisaError.rejected("World-writable path component") }
        }
    }
    public func inspect(_ path: String, now: Date = Date()) throws -> IndexedFile {
        guard path.hasPrefix("/"), !path.contains("\0"),
              !path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 || $0.properties.generalCategory == .format }),
              Paths.normalized(path) == path,
              let root = roots.first(where: { Self.within(path, $0) }), path != root else {
            throw BrisaError.rejected("Not a canonical path inside an indexed root")
        }
        if let why = exclusion(path) { throw BrisaError.rejected(why) }
        try Self.rejectSymlinks(path)
        var st = stat()
        guard lstat(path, &st) == 0, st.st_mode & S_IFMT == S_IFREG,
              st.st_uid == getuid(), st.st_nlink == 1, st.st_size >= 0,
              st.st_flags & UInt32(UF_IMMUTABLE | SF_IMMUTABLE | UF_APPEND | SF_APPEND | SF_DATALESS) == 0,
              access(path, R_OK | W_OK) == 0,
              access(URL(fileURLWithPath: path).deletingLastPathComponent().path, W_OK | X_OK) == 0 else {
            throw BrisaError.rejected("Not an ordinary, singly linked, readable and writable owned file")
        }
        let values = try URL(fileURLWithPath: path).resourceValues(forKeys: [.isUbiquitousItemKey])
        guard values.isUbiquitousItem != true else { throw BrisaError.rejected("Cloud-managed file") }
        // A working copy is never a cache, even if it lives below a cache root.
        var parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        while Self.within(parent.path, home) {
            if FileManager.default.fileExists(atPath: parent.appendingPathComponent(".git").path) {
                throw BrisaError.rejected("Git working copy; only official Git operations may remove worktrees")
            }
            if parent.path == home { break }
            parent.deleteLastPathComponent()
        }
        let identity = Self.identity(st)
        let modified = Date(timeIntervalSince1970: identity.modified)
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        let isCache = Self.within(path, home + "/Library/Caches") && ["cache", "tmp"].contains(ext)
        let isLog = Self.within(path, home + "/Library/Logs") && ext == "log"
        let category: Category = isCache ? .cache : (isLog ? .log : .other)
        let threshold = isLog ? max(minimumAge, 30 * 86400) : minimumAge
        let oldEnough = now.timeIntervalSince(modified) >= threshold && now.timeIntervalSince1970 >= identity.changed
        let eligible = category != .other && oldEnough && st.st_size > 0
        return IndexedFile(id: "\(st.st_dev):\(st.st_ino):\(identity.modified):\(identity.changed)", path: path, root: root,
            identity: identity, allocatedBytes: Int64(st.st_blocks) * 512, category: category, modifiedAt: modified,
            eligible: eligible, reason: category == .other ? "inventory_only" : (oldEnough ? "old_known_extension" : "recent_file"), confidence: eligible ? "medium" : "none")
    }
    public static func identity(_ st: stat) -> FileIdentity {
        FileIdentity(device: UInt64(UInt32(bitPattern: st.st_dev)), inode: st.st_ino, size: st.st_size,
            modified: Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9,
            changed: Double(st.st_ctimespec.tv_sec) + Double(st.st_ctimespec.tv_nsec) / 1e9,
            links: st.st_nlink, mode: st.st_mode, owner: st.st_uid)
    }
    public func revalidate(_ file: IndexedFile) throws -> IndexedFile {
        guard file.isReviewable else {
            throw BrisaError.rejected("Item is inventory-only or locked by catalog policy")
        }
        let fresh = try inspect(file.path)
        guard fresh.eligible, fresh.identity == file.identity else { throw BrisaError.rejected("File changed since analysis") }
        return fresh
    }
}
