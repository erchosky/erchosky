import Foundation

/// Pure inventory filtering, shared by cached UI projections and command queries.
public struct InventoryQuery: Hashable, Sendable {
    public var query = ""
    public var category = "all"
    public var sizeFilter = "all"
    public var typeFilter = "all"
    public var statusFilter = "all"
    public var dateFilter = "all"
    public var locationFilter = "all"
    public var sortOrder = "allocated_desc"
    public var spaceMapFolderPrefix: String?
    public var inventoryRoots: [String] = []
    public var home = NSHomeDirectory()
    // Fixed for a projection; hardware ticks should not invalidate the inventory.
    public var now = Date()
    public init() {}

    public func apply(to files: [IndexedFile]) -> [IndexedFile] {
        sortFiles(filterUnsorted(files))
    }

    public func filterUnsorted(_ files: [IndexedFile]) -> [IndexedFile] {
        guard !files.isEmpty else { return [] }
        let prepared = PreparedFilter(filter: self)
        var result: [IndexedFile] = []
        result.reserveCapacity(min(files.count, 512))
        for file in files where prepared.matches(file) {
            result.append(file)
        }
        return result
    }

    public static func matchesCategory(_ file: IndexedFile, filter: String) -> Bool {
        switch filter {
        case "all": return true
        case "eligible": return file.isReviewable
        case "inventory": return !file.isReviewable
        case "cache", "log", "other": return file.category.rawValue == filter
        default: return file.storageCategory.rawValue == filter
        }
    }

    public static func matchesQuery(_ file: IndexedFile, search: String) -> Bool {
        guard !search.isEmpty else { return true }
        let matcher = QueryMatcher(search: search)
        return matcher.matches(file)
    }

    public func matchesAdvancedFilters(_ file: IndexedFile) -> Bool {
        PreparedFilter(filter: self).matchesAdvanced(file)
    }

    private struct QueryMatcher {
        let raw: String
        let asciiLowerNeedle: [UInt8]?

        init(search: String) {
            self.raw = search
            if !search.isEmpty, search.utf8.allSatisfy({ $0 < 0x80 }) {
                self.asciiLowerNeedle = search.utf8.map { ($0 >= 65 && $0 <= 90) ? ($0 + 32) : $0 }
            } else {
                self.asciiLowerNeedle = nil
            }
        }

        func matches(_ file: IndexedFile) -> Bool {
            if raw.isEmpty { return true }
            if contains(file.titleEN) || contains(file.titleES) || contains(file.path) { return true }
            if let sourceGroup = file.sourceGroup, contains(sourceGroup) { return true }
            if let ruleID = file.ruleID, contains(ruleID) { return true }
            if contains(file.explanationEN) || contains(file.explanationES) { return true }
            if let provenance = file.provenance, contains(provenance) { return true }
            if let upstream = file.upstreamProvenance?.upstreamID, contains(upstream) { return true }
            return false
        }

        private func contains(_ haystack: String) -> Bool {
            guard let needle = asciiLowerNeedle else {
                return haystack.localizedCaseInsensitiveContains(raw)
            }
            if haystack.isEmpty { return false }
            let m = needle.count
            var nonASCII = false
            // Scan UTF-8 bytes directly for pure ASCII strings; fall back cleanly on non-ASCII characters.
            let matched = haystack.utf8.withContiguousStorageIfAvailable { buf -> Bool in
                let n = buf.count
                for i in 0..<n {
                    if buf[i] >= 0x80 {
                        nonASCII = true
                        return false
                    }
                }
                guard n >= m else { return false }
                let first = needle[0]
                let limit = n - m
                var i = 0
                while i <= limit {
                    let b = buf[i]
                    let lb = (b >= 65 && b <= 90) ? (b + 32) : b
                    if lb == first {
                        var j = 1
                        while j < m {
                            let hb = buf[i + j]
                            let lhb = (hb >= 65 && hb <= 90) ? (hb + 32) : hb
                            if lhb != needle[j] { break }
                            j += 1
                        }
                        if j == m { return true }
                    }
                    i += 1
                }
                return false
            }
            if let matched {
                if nonASCII {
                    return haystack.localizedCaseInsensitiveContains(raw)
                }
                return matched
            }
            let bytes = Array(haystack.utf8)
            for b in bytes where b >= 0x80 {
                return haystack.localizedCaseInsensitiveContains(raw)
            }
            let n = bytes.count
            guard n >= m else { return false }
            let first = needle[0]
            let limit = n - m
            var i = 0
            while i <= limit {
                let b = bytes[i]
                let lb = (b >= 65 && b <= 90) ? (b + 32) : b
                if lb == first {
                    var j = 1
                    while j < m {
                        let hb = bytes[i + j]
                        let lhb = (hb >= 65 && hb <= 90) ? (hb + 32) : hb
                        if lhb != needle[j] { break }
                        j += 1
                    }
                    if j == m { return true }
                }
                i += 1
            }
            return false
        }
    }

    private struct PreparedFilter {
        let queryMatcher: QueryMatcher
        let category: String
        let sizeFilter: String
        let typeFilter: String
        let statusFilter: String
        let dateFilter: String
        let locationFilter: String
        let spaceMapFolderPrefix: String?
        let inventoryRoots: [String]
        let nowTimestamp: TimeInterval
        let homeWithSlash: String
        let homeLibraryPrefix: String

        init(filter: InventoryQuery) {
            self.queryMatcher = QueryMatcher(search: filter.query)
            self.category = filter.category
            self.sizeFilter = filter.sizeFilter
            self.typeFilter = filter.typeFilter
            self.statusFilter = filter.statusFilter
            self.dateFilter = filter.dateFilter
            self.locationFilter = filter.locationFilter
            self.spaceMapFolderPrefix = filter.spaceMapFolderPrefix
            self.inventoryRoots = filter.inventoryRoots
            self.nowTimestamp = filter.now.timeIntervalSince1970
            self.homeWithSlash = filter.home + "/"
            self.homeLibraryPrefix = filter.home + "/Library/"
        }

        func matches(_ file: IndexedFile) -> Bool {
            InventoryQuery.matchesCategory(file, filter: category)
                && matchesAdvanced(file)
                && queryMatcher.matches(file)
        }

        func matchesAdvanced(_ file: IndexedFile) -> Bool {
            if let prefix = spaceMapFolderPrefix, !SafetyPolicy.within(file.path, prefix) {
                return false
            }
            switch sizeFilter {
            case "gt10m":
                if file.allocatedBytes <= 10 * 1_048_576 { return false }
            case "gt100m":
                if file.allocatedBytes <= 100 * 1_048_576 { return false }
            case "gt1g":
                if file.allocatedBytes <= 1_073_741_824 { return false }
            case "zero_allocated":
                if !(file.allocatedBytes == 0 && file.logicalBytes > 0) { return false }
            default:
                break
            }

            switch typeFilter {
            case "file":
                if file.isDirectory { return false }
            case "directory":
                if !file.isDirectory { return false }
            default:
                break
            }

            switch statusFilter {
            case "eligible":
                if !file.isReviewable { return false }
            case "inventory":
                if file.isReviewable { return false }
            case "in_use":
                if file.usageState.status != "active_process" && file.usageState.status != "open_file" && file.cleanupEligibility != .lockedActiveProcess && file.cleanupEligibility != .lockedOpenFile {
                    return false
                }
            case "partial":
                if !file.isPartial { return false }
            default:
                break
            }

            if dateFilter != "all" {
                let age = nowTimestamp - file.modifiedAt.timeIntervalSince1970
                switch dateFilter {
                case "lt24h":
                    if age >= 86_400 { return false }
                case "gt7d":
                    if age <= 7 * 86_400 { return false }
                case "gt30d":
                    if age <= 30 * 86_400 { return false }
                default:
                    break
                }
            }

            switch locationFilter {
            case "library":
                if !file.path.hasPrefix(homeLibraryPrefix) { return false }
            case "hidden":
                let rel: Substring = file.path.hasPrefix(homeWithSlash)
                    ? file.path.dropFirst(homeWithSlash.count)
                    : file.path[...]
                if !rel.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { return false }
            case "projects":
                let inProjectRoot = inventoryRoots.contains { SafetyPolicy.within(file.path, $0) }
                if !inProjectRoot { return false }
            default:
                break
            }

            return true
        }
    }

    public func sortFiles(_ items: [IndexedFile]) -> [IndexedFile] {
        if sortOrder == "name_asc" {
            let named: [(file: IndexedFile, name: String)] = items.map { file in
                let base: Substring
                if let slash = file.path.lastIndex(of: "/") {
                    let next = file.path.index(after: slash)
                    base = next < file.path.endIndex ? file.path[next...] : Substring(file.path)
                } else {
                    base = Substring(file.path)
                }
                return (file: file, name: base.lowercased())
            }
            let sorted = named.sorted { left, right in
                if left.name != right.name { return left.name < right.name }
                return left.file.path < right.file.path
            }
            return sorted.map { $0.file }
        }
        return items.sorted { a, b in
            switch sortOrder {
            case "logical_desc":
                if a.logicalBytes != b.logicalBytes { return a.logicalBytes > b.logicalBytes }
                if a.allocatedBytes != b.allocatedBytes { return a.allocatedBytes > b.allocatedBytes }
                return a.path < b.path
            case "modified_desc":
                if a.modifiedAt != b.modifiedAt { return a.modifiedAt > b.modifiedAt }
                if a.allocatedBytes != b.allocatedBytes { return a.allocatedBytes > b.allocatedBytes }
                return a.path < b.path
            default: // "allocated_desc" — NEVER substitute logicalBytes when allocatedBytes == 0
                if a.allocatedBytes != b.allocatedBytes { return a.allocatedBytes > b.allocatedBytes }
                if a.logicalBytes != b.logicalBytes { return a.logicalBytes > b.logicalBytes }
                return a.path < b.path
            }
        }
    }

}
