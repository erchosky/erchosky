import Foundation
import Darwin

/// Shared, bounded application discovery. Vendor/Utilities folders are visited;
/// application bundles and symlinks are never traversed.
public enum ApplicationDiscovery {
    public struct Result: Sendable {
        public let urls: [URL]
        public let complete: Bool
    }

    public static func discover(in roots: [String], maxDepth: Int = 3, maxEntries: Int = 10_000,
                                control: ScanControl = ScanControl()) -> Result {
        var urls: [URL] = [], seen = Set<String>(), examined = 0, complete = true
        func walk(_ path: String, depth: Int) {
            guard !control.shouldStop, examined < maxEntries else { complete = false; return }
            guard !ReadAuthorizationPolicy.hasSymlinkComponent(path) else { complete = false; return }
            guard let directory = Paths.openDirectory(path) else {
                if errno != ENOENT { complete = false }
                return
            }
            defer { closedir(directory) }
            while let entry = readdir(directory) {
                let name = withUnsafePointer(to: entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
                }
                if name == "." || name == ".." { continue }
                guard !control.shouldStop, examined < maxEntries else { complete = false; break }
                examined += 1
                if name.hasPrefix(".") { continue }
                let child = path + "/" + name
                var st = stat()
                guard lstat(child, &st) == 0 else { complete = false; continue }
                guard st.st_mode & S_IFMT == S_IFDIR else { continue }
                if name.lowercased().hasSuffix(".app") {
                    if seen.insert(child).inserted { urls.append(URL(fileURLWithPath: child)) }
                } else if depth < maxDepth { walk(child, depth: depth + 1) }
                else { complete = false }
            }
        }
        for root in Set(roots.map(Paths.normalized)).sorted() {
            var st = stat()
            if lstat(root, &st) != 0, errno == ENOENT { continue }
            walk(root, depth: 0)
        }
        return Result(urls: urls.sorted { $0.path < $1.path }, complete: complete)
    }
}
