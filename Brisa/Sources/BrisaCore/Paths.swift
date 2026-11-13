import Foundation
import Darwin

public enum Paths {
    /// Never block on a FIFO/device or follow a symlink while trying to enumerate a directory.
    public static func openDirectory(_ path: String) -> UnsafeMutablePointer<DIR>? {
        let fd = Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        guard let directory = fdopendir(fd) else { close(fd); return nil }
        return directory
    }

    /// Indexed ancestor lookup avoids scanning every claimed path for each candidate.
    public static func containsAncestor(of path: String, in paths: Set<String>) -> Bool {
        var current = path
        while !current.isEmpty {
            if paths.contains(current) { return true }
            guard let slash = current.lastIndex(of: "/") else { break }
            if slash == current.startIndex { return paths.contains("/") }
            current = String(current[..<slash])
        }
        return false
    }

    /// Returns true when `path` contains no empty segments (`//`), `.` / `..` traversal, or trailing `/`.
    public static func isAlreadyNormalized(_ path: String) -> Bool {
        let bytes = path.utf8
        if bytes.isEmpty { return true }
        if bytes.count > 1 && bytes.last == 47 { return false }
        var prevSlash = false
        var dotCount = 0
        var atSegmentStart = true
        for byte in bytes {
            if byte == 47 {
                if prevSlash { return false }
                if !atSegmentStart && (dotCount == 1 || dotCount == 2) { return false }
                prevSlash = true
                dotCount = 0
                atSegmentStart = true
            } else {
                prevSlash = false
                if atSegmentStart {
                    dotCount = (byte == 46) ? 1 : -1
                    atSegmentStart = false
                } else if dotCount == 1 && byte == 46 {
                    dotCount = 2
                } else {
                    dotCount = -1
                }
            }
        }
        return dotCount != 1 && dotCount != 2
    }

    /// Pure lexical normalization. Foundation's standardization rewrites /private/var
    /// to its /var symlink on macOS, which is unsuitable for no-symlink validation.
    public static func normalized(_ path: String) -> String {
        if isAlreadyNormalized(path) { return path }
        var parts: [Substring] = []
        for part in path.split(separator: "/") {
            if part == "." { continue }
            if part == ".." { if !parts.isEmpty { parts.removeLast() } }
            else { parts.append(part) }
        }
        return (path.hasPrefix("/") ? "/" : "") + parts.joined(separator: "/")
    }
    /// Only for OS-provided locations (temporary directory / home), never to approve
    /// an arbitrary candidate symlink. Candidates must pass rejectSymlinks first.
    public static func systemLocation(_ path: String) throws -> String {
        guard let pointer = realpath(path, nil) else { throw BrisaError.io("Cannot resolve OS-provided directory") }
        defer { free(pointer) }
        return String(cString: pointer)
    }
}
