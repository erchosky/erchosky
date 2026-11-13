import Foundation
import Darwin

public struct MatchedCandidate: Equatable, Sendable {
    public let path: String
    public let rule: CatalogRule
    public let matchedPattern: String
    public let isDirectory: Bool
}

public struct PatternMatchStats: Sendable {
    public var deadline: Date = .distantFuture
    public var existingBaseRoots: Int = 0
    public var accessDeniedCount: Int = 0
    public var examinedEntries: Int = 0
    public var hitBudgetOrCancelled: Bool = false
    public var errors: [String] = []
}

public enum PatternMatcher {
    private static let catchAllRuleIDs: Set<String> = [
        "user-caches",
        "user-log-folders",
        "user-logs",
        "temp-folders",
        "app-support-leftovers",
        "container-leftovers",
        "preferences-leftovers"
    ]

    public static func specificityScore(for rule: CatalogRule) -> Int {
        var score = 0
        if catchAllRuleIDs.contains(rule.id) {
            score -= 200
        }
        if !rule.inside.isEmpty { score += 120 }
        if !rule.notInside.isEmpty { score += 100 }
        if !rule.near.isEmpty { score += 110 }

        let maxSegments = rule.patterns.map { $0.split(separator: "/").count }.max() ?? 1
        score += maxSegments * 12

        let allLiteralLeaf = rule.patterns.allSatisfy { pat in
            guard let last = pat.split(separator: "/").last else { return false }
            return !last.contains("*") && !last.contains("?") && !last.contains("[")
        }
        if allLiteralLeaf { score += 35 }

        let wildcardCount = rule.patterns.reduce(0) { acc, pat in
            acc + pat.filter { $0 == "*" || $0 == "?" }.count
        }
        score -= min(wildcardCount * 3, 30)
        return score
    }

    public static func sortBySpecificity(_ rules: [CatalogRule]) -> [CatalogRule] {
        rules
            .map { (rule: $0, score: specificityScore(for: $0)) }
            .sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                return a.rule.id < b.rule.id
            }
            .map(\.rule)
    }

    public static func expand(
        rule: CatalogRule,
        readPolicy: ReadAuthorizationPolicy,
        claimedPaths: Set<String>,
        neverTouchedPaths: Set<String>,
        cancellation: CancellationFlag,
        maxRecursiveDepth: Int = 4,
        maxEntriesPerRule: Int = 2500,
        stats: inout PatternMatchStats
    ) -> [MatchedCandidate] {
        var results: [MatchedCandidate] = []
        var seenInRule = Set<String>()
        var nearSiblingCache: [String: [String]?] = [:]

        for rawPattern in rule.patterns {
            if cancellation.isCancelled || Date() >= stats.deadline || stats.examinedEntries >= maxEntriesPerRule {
                stats.hitBudgetOrCancelled = true
                break
            }

            let candidates = expandSinglePattern(
                rawPattern,
                rule: rule,
                readPolicy: readPolicy,
                cancellation: cancellation,
                maxRecursiveDepth: maxRecursiveDepth,
                maxEntriesPerRule: maxEntriesPerRule,
                stats: &stats
            )

            for (path, isDir) in candidates {
                if cancellation.isCancelled || Date() >= stats.deadline {
                    stats.hitBudgetOrCancelled = true
                    break
                }
                guard seenInRule.insert(path).inserted else { continue }

                // Skip paths inside or identical to neverTouchedPaths
                if Paths.containsAncestor(of: path, in: neverTouchedPaths) {
                    continue
                }

                // Skip paths already claimed or inside an already claimed directory.
                // Note: if `path` is a parent directory containing a claimed child directory,
                // we do NOT skip `path` here; instead, `StorageMeasurement.measure` skips the
                // claimed child subtree and measures only the unclaimed sibling files in `path`.
                if Paths.containsAncestor(of: path, in: claimedPaths) {
                    continue
                }

                // Check structural guards: near, inside, notInside
                if !rule.near.isEmpty, !checkNearCached(path: path, anchors: rule.near, siblingCache: &nearSiblingCache) {
                    continue
                }
                if !rule.inside.isEmpty, !checkInside(path: path, isDirectory: isDir, markers: rule.inside) {
                    continue
                }
                if !rule.notInside.isEmpty, !checkNotInside(path: path, isDirectory: isDir, markers: rule.notInside) {
                    continue
                }

                // Special filter for colima-lima: skip _config, _networks, and the _disks container itself (since _disks/* is expanded)
                if rule.id == "colima-lima" {
                    let name = lastPathComponent(path)
                    if name == "_config" || name == "_networks" || name == "_disks" || name.hasPrefix(".") {
                        continue
                    }
                }

                results.append(MatchedCandidate(path: path, rule: rule, matchedPattern: rawPattern, isDirectory: isDir))
            }
        }
        return results
    }

    private static func expandSinglePattern(
        _ rawPattern: String,
        rule: CatalogRule,
        readPolicy: ReadAuthorizationPolicy,
        cancellation: CancellationFlag,
        maxRecursiveDepth: Int,
        maxEntriesPerRule: Int,
        stats: inout PatternMatchStats
    ) -> [(String, Bool)] {
        // Case 1: Relative recursive pattern "**/..." or "~/\**/..."
        if rawPattern.hasPrefix("**/") || rawPattern.hasPrefix("~/**/") {
            let tail = rawPattern.hasPrefix("**/")
                ? String(rawPattern.dropFirst(3))
                : String(rawPattern.dropFirst(5))
            return expandBoundedRecursiveProjectPattern(
                tailPattern: tail,
                readPolicy: readPolicy,
                cancellation: cancellation,
                maxDepth: maxRecursiveDepth,
                maxEntries: maxEntriesPerRule,
                stats: &stats
            )
        }

        // Case 2: Concrete path pattern ("~/..." or "/...")
        let resolvedPattern: String
        let isSystemPattern: Bool
        if rawPattern.hasPrefix("~/") {
            resolvedPattern = readPolicy.home + String(rawPattern.dropFirst(1))
            isSystemPattern = false
        } else if rawPattern.hasPrefix("/") {
            if rawPattern.hasPrefix("/Volumes/") {
                // Never scan external/mounted volumes automatically
                return []
            }
            if !readPolicy.allowSystemLocations && readPolicy.systemRootPrefix == nil {
                return []
            }
            resolvedPattern = (readPolicy.systemRootPrefix ?? "") + rawPattern
            isSystemPattern = true
        } else {
            return []
        }

        let segments = resolvedPattern.split(separator: "/").map(String.init)
        guard !segments.isEmpty else { return [] }

        // Determine longest literal prefix to check base installation existence
        var literalCount = 0
        for seg in segments {
            if isWildcardSegment(seg) { break }
            literalCount += 1
        }

        let baseCheckCount = max(1, min(literalCount, segments.count))
        let basePrefix = "/" + segments.prefix(baseCheckCount).joined(separator: "/")

        if readPolicy.requiresUnauthedTCCPrompt(basePrefix) {
            stats.accessDeniedCount += 1
            if stats.errors.count < 30 {
                stats.errors.append("TCC permission required: \(basePrefix)")
            }
            return []
        }

        // Check if the parent/base tool location exists
        let existenceProbePath = basePrefix

        var probeStat = stat()
        if lstat(existenceProbePath, &probeStat) == 0 {
            if (probeStat.st_mode & S_IFMT) != S_IFLNK {
                stats.existingBaseRoots += 1
            }
        } else if errno == EACCES || errno == EPERM {
            stats.accessDeniedCount += 1
            if stats.errors.count < 30 {
                stats.errors.append("Permission denied: \(existenceProbePath)")
            }
            return []
        } else {
            return []
        }

        var matches: [(String, Bool)] = []
        let startPath = literalCount > 0 ? basePrefix : "/"
        let remainingSegments = Array(segments.dropFirst(literalCount))

        walkSegments(
            currentPath: startPath,
            remaining: remainingSegments,
            isSystemPattern: isSystemPattern,
            readPolicy: readPolicy,
            cancellation: cancellation,
            maxRecursiveDepth: maxRecursiveDepth,
            maxEntries: maxEntriesPerRule,
            stats: &stats,
            results: &matches
        )

        return matches
    }

    private static func walkSegments(
        currentPath: String,
        remaining: [String],
        isSystemPattern: Bool,
        readPolicy: ReadAuthorizationPolicy,
        cancellation: CancellationFlag,
        maxRecursiveDepth: Int,
        maxEntries: Int,
        stats: inout PatternMatchStats,
        results: inout [(String, Bool)]
    ) {
        if cancellation.isCancelled || Date() >= stats.deadline || (stats.examinedEntries >= maxEntries && !remaining.isEmpty) {
            stats.hitBudgetOrCancelled = true
            return
        }

        if remaining.isEmpty {
            guard readPolicy.evaluate(currentPath, checkSymlinks: true) == .allowed else { return }
            var st = stat()
            guard lstat(currentPath, &st) == 0 else {
                if errno == EACCES || errno == EPERM { stats.accessDeniedCount += 1 }
                return
            }
            let mode = st.st_mode & S_IFMT
            guard mode == S_IFREG || mode == S_IFDIR else { return }
            if isSystemPattern && (currentPath.hasPrefix("/private/tmp/") || currentPath.hasPrefix("/private/var/tmp/") || currentPath.hasPrefix("/private/var/folders/") || (readPolicy.systemRootPrefix != nil && (currentPath.contains("/private/tmp/") || currentPath.contains("/private/var/tmp/") || currentPath.contains("/private/var/folders/")))) {
                guard st.st_uid == getuid() else { return }
            }
            results.append((currentPath, mode == S_IFDIR))
            return
        }

        let head = remaining[0]
        let tail = Array(remaining.dropFirst())

        if head == "**" {
            // Bounded recursive expansion under a concrete prefix (e.g. ~/Library/Application Support/Claude/**/*.bundle)
            walkBoundedSubtree(
                basePath: currentPath,
                depth: 0,
                maxDepth: maxRecursiveDepth,
                tail: tail,
                isSystemPattern: isSystemPattern,
                readPolicy: readPolicy,
                cancellation: cancellation,
                maxEntries: maxEntries,
                stats: &stats,
                results: &results
            )
            return
        }

        if !isWildcardSegment(head) {
            let nextPath = currentPath == "/" ? "/\(head)" : "\(currentPath)/\(head)"
            if readPolicy.requiresUnauthedTCCPrompt(nextPath) {
                stats.accessDeniedCount += 1
                stats.errors.append("TCC permission required: " + nextPath)
                return
            }
            stats.examinedEntries += 1
            var st = stat()
            guard lstat(nextPath, &st) == 0 else {
                if errno == EACCES || errno == EPERM {
                    stats.accessDeniedCount += 1
                }
                return
            }
            guard (st.st_mode & S_IFMT) != S_IFLNK else { return }
            walkSegments(
                currentPath: nextPath,
                remaining: tail,
                isSystemPattern: isSystemPattern,
                readPolicy: readPolicy,
                cancellation: cancellation,
                maxRecursiveDepth: maxRecursiveDepth,
                maxEntries: maxEntries,
                stats: &stats,
                results: &results
            )
            return
        }

        // Wildcard segment: enumerate direct children via POSIX opendir/readdir
        if readPolicy.requiresUnauthedTCCPrompt(currentPath) {
            stats.accessDeniedCount += 1
            if stats.errors.count < 30 {
                stats.errors.append("TCC permission required: \(currentPath)")
            }
            return
        }
        guard let dir = Paths.openDirectory(currentPath) else {
            if errno == EACCES || errno == EPERM {
                stats.accessDeniedCount += 1
                if stats.errors.count < 30 {
                    stats.errors.append("Unreadable directory: \(currentPath)")
                }
            }
            return
        }
        defer { closedir(dir) }

        while let entry = readdir(dir) {
            if cancellation.isCancelled || Date() >= stats.deadline || stats.examinedEntries >= maxEntries {
                stats.hitBudgetOrCancelled = true
                return
            }
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." || name == ".DS_Store" { continue }
            stats.examinedEntries += 1
            if !head.hasPrefix(".") && name.hasPrefix(".") { continue }
            guard matchesSegment(name, pattern: head) else { continue }
            let nextPath = currentPath == "/" ? "/\(name)" : "\(currentPath)/\(name)"
            if readPolicy.requiresUnauthedTCCPrompt(nextPath) { continue }
            var st = stat()
            guard lstat(nextPath, &st) == 0 else { continue }
            guard (st.st_mode & S_IFMT) != S_IFLNK else { continue }
            if isSystemPattern && currentPath.hasPrefix("/private/var/folders/") && st.st_uid != getuid() {
                continue
            }
            walkSegments(
                currentPath: nextPath,
                remaining: tail,
                isSystemPattern: isSystemPattern,
                readPolicy: readPolicy,
                cancellation: cancellation,
                maxRecursiveDepth: maxRecursiveDepth,
                maxEntries: maxEntries,
                stats: &stats,
                results: &results
            )
        }
    }

    private static func walkBoundedSubtree(
        basePath: String,
        depth: Int,
        maxDepth: Int,
        tail: [String],
        isSystemPattern: Bool,
        readPolicy: ReadAuthorizationPolicy,
        cancellation: CancellationFlag,
        maxEntries: Int,
        stats: inout PatternMatchStats,
        results: inout [(String, Bool)]
    ) {
        if cancellation.isCancelled || Date() >= stats.deadline || stats.examinedEntries >= maxEntries || depth > maxDepth {
            if stats.examinedEntries >= maxEntries || cancellation.isCancelled || Date() >= stats.deadline {
                stats.hitBudgetOrCancelled = true
            }
            return
        }

        // Try matching tail at current depth
        walkSegments(
            currentPath: basePath,
            remaining: tail,
            isSystemPattern: isSystemPattern,
            readPolicy: readPolicy,
            cancellation: cancellation,
            maxRecursiveDepth: maxDepth - depth,
            maxEntries: maxEntries,
            stats: &stats,
            results: &results
        )

        guard depth < maxDepth, readPolicy.evaluate(basePath) == .allowed,
              !readPolicy.requiresUnauthedTCCPrompt(basePath), let dir = Paths.openDirectory(basePath) else { return }
        defer { closedir(dir) }

        while let entry = readdir(dir) {
            if cancellation.isCancelled || Date() >= stats.deadline || stats.examinedEntries >= maxEntries {
                stats.hitBudgetOrCancelled = true
                return
            }
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }
            stats.examinedEntries += 1
            if name.hasPrefix(".") { continue }
            let childPath = basePath == "/" ? "/\(name)" : "\(basePath)/\(name)"
            if readPolicy.requiresUnauthedTCCPrompt(childPath) { continue }
            var st = stat()
            if lstat(childPath, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR {
                // Do not descend into matched bundles (.bundle, .app, .framework)
                if name.hasSuffix(".bundle") || name.hasSuffix(".app") || name.hasSuffix(".framework") {
                    continue
                }
            guard readPolicy.evaluate(childPath, checkSymlinks: false) == .allowed else { continue }
            walkBoundedSubtree(
                basePath: childPath,
                depth: depth + 1,
                maxDepth: maxDepth,
                tail: tail,
                isSystemPattern: isSystemPattern,
                readPolicy: readPolicy,
                cancellation: cancellation,
                maxEntries: maxEntries,
                stats: &stats,
                results: &results
            )
            }
        }
    }

    private static func expandBoundedRecursiveProjectPattern(
        tailPattern: String,
        readPolicy: ReadAuthorizationPolicy,
        cancellation: CancellationFlag,
        maxDepth: Int,
        maxEntries: Int,
        stats: inout PatternMatchStats
    ) -> [(String, Bool)] {
        let defaultCaches = readPolicy.home + "/Library/Caches"
        let defaultLogs = readPolicy.home + "/Library/Logs"
        let eligibleProjectRoots = readPolicy.projectRoots.filter { root in
            !SafetyPolicy.within(root, defaultCaches) && !SafetyPolicy.within(root, defaultLogs)
        }
        guard !eligibleProjectRoots.isEmpty else { return [] }

        let tailSegments = tailPattern.split(separator: "/").map(String.init)
        guard !tailSegments.isEmpty else { return [] }

        var results: [(String, Bool)] = []
        for root in eligibleProjectRoots {
            if readPolicy.requiresUnauthedTCCPrompt(root) {
                stats.accessDeniedCount += 1
                continue
            }
            var st = stat()
            guard lstat(root, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else { continue }
            stats.existingBaseRoots += 1
            walkBoundedProjectTree(
                currentDir: root,
                depth: 0,
                maxDepth: maxDepth,
                tailSegments: tailSegments,
                readPolicy: readPolicy,
                cancellation: cancellation,
                maxEntries: maxEntries,
                stats: &stats,
                results: &results
            )
        }
        return results
    }

    private static func walkBoundedProjectTree(
        currentDir: String,
        depth: Int,
        maxDepth: Int,
        tailSegments: [String],
        readPolicy: ReadAuthorizationPolicy,
        cancellation: CancellationFlag,
        maxEntries: Int,
        stats: inout PatternMatchStats,
        results: inout [(String, Bool)]
    ) {
        if cancellation.isCancelled || Date() >= stats.deadline || stats.examinedEntries >= maxEntries || depth > maxDepth {
            if stats.examinedEntries >= maxEntries || cancellation.isCancelled || Date() >= stats.deadline {
                stats.hitBudgetOrCancelled = true
            }
            return
        }

        // Check if tailSegments match starting at currentDir
        let countBefore = results.count
        walkSegments(
            currentPath: currentDir,
            remaining: tailSegments,
            isSystemPattern: false,
            readPolicy: readPolicy,
            cancellation: cancellation,
            maxRecursiveDepth: 1,
            maxEntries: maxEntries,
            stats: &stats,
            results: &results
        )
        let matchedHere = Set(results.dropFirst(countBefore).map(\.0))

        guard depth < maxDepth, readPolicy.evaluate(currentDir) == .allowed,
              !readPolicy.requiresUnauthedTCCPrompt(currentDir), let dir = Paths.openDirectory(currentDir) else { return }
        defer { closedir(dir) }

        while let entry = readdir(dir) {
            if cancellation.isCancelled || Date() >= stats.deadline || stats.examinedEntries >= maxEntries {
                stats.hitBudgetOrCancelled = true
                return
            }
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }
            stats.examinedEntries += 1
            if name.hasPrefix(".") { continue }
            if name == "node_modules" || name == "Pods" || name == "DerivedData" || name == "build" || name == "target" {
                continue
            }
            let childPath = "\(currentDir)/\(name)"
            if matchedHere.contains(childPath) { continue }
            var st = stat()
            if lstat(childPath, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR {
            guard readPolicy.evaluate(childPath, checkSymlinks: false) == .allowed else { continue }
            walkBoundedProjectTree(
                currentDir: childPath,
                depth: depth + 1,
                maxDepth: maxDepth,
                tailSegments: tailSegments,
                readPolicy: readPolicy,
                cancellation: cancellation,
                maxEntries: maxEntries,
                stats: &stats,
                results: &results
            )
            }
        }
    }

    public static func checkNear(path: String, anchors: [String], readPolicy: ReadAuthorizationPolicy) -> Bool {
        var cache: [String: [String]?] = [:]
        return checkNearCached(path: path, anchors: anchors, siblingCache: &cache)
    }

    private static func checkNearCached(
        path: String,
        anchors: [String],
        siblingCache: inout [String: [String]?]
    ) -> Bool {
        let parent = parentPath(path)
        let siblingNames: [String]
        if let cached = siblingCache[parent] {
            guard let resolved = cached else { return false }
            siblingNames = resolved
        } else if let loaded = loadNonSymlinkSiblingNames(in: parent) {
            siblingCache[parent] = loaded
            siblingNames = loaded
        } else {
            siblingCache[parent] = .some(nil)
            return false
        }

        for anchor in anchors {
            if siblingNames.contains(where: { matchesSegment($0, pattern: anchor) }) {
                return true
            }
        }
        return false
    }

    private static func loadNonSymlinkSiblingNames(in parent: String) -> [String]? {
        guard let dir = Paths.openDirectory(parent) else { return nil }
        defer { closedir(dir) }

        var siblingNames: [String] = []
        while let entry = readdir(dir) {
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }
            let siblingPath = parent == "/" ? "/\(name)" : "\(parent)/\(name)"
            var st = stat()
            if lstat(siblingPath, &st) == 0 && (st.st_mode & S_IFMT) != S_IFLNK {
                siblingNames.append(name)
            }
        }
        return siblingNames
    }

    private static func parentPath(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "." }
        if slash == path.startIndex { return "/" }
        return String(path[..<slash])
    }

    private static func lastPathComponent(_ path: String) -> Substring {
        guard let slash = path.lastIndex(of: "/") else { return Substring(path) }
        return path[path.index(after: slash)...]
    }

    public static func checkInside(path: String, isDirectory: Bool, markers: [String]) -> Bool {
        guard isDirectory else { return false }
        for marker in markers {
            let full = "\(path)/\(marker)"
            if !ReadAuthorizationPolicy.hasSymlinkComponent(full, stopAt: path) {
                var st = stat()
                if lstat(full, &st) == 0 && (st.st_mode & S_IFMT) != S_IFLNK {
                    return true
                }
            }
        }
        return false
    }

    public static func checkNotInside(path: String, isDirectory: Bool, markers: [String]) -> Bool {
        guard isDirectory else { return true }
        for marker in markers {
            let full = "\(path)/\(marker)"
            var st = stat()
            if lstat(full, &st) == 0 {
                return false
            }
        }
        return true
    }

    public static func isWildcardSegment(_ segment: String) -> Bool {
        segment.contains("*") || segment.contains("?") || segment.contains("[")
    }

    public static func matchesSegment(_ text: String, pattern: String) -> Bool {
        text.withCString { tPtr in
            pattern.withCString { pPtr in
                fnmatch(pPtr, tPtr, 0) == 0
            }
        }
    }
}
