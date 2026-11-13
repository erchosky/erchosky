import Foundation

public struct SpaceMapBreadcrumb: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let category: StorageCategory?
    public let folderPrefix: String?

    public init(id: String, title: String, category: StorageCategory? = nil, folderPrefix: String? = nil) {
        self.id = id
        self.title = title
        self.category = category
        self.folderPrefix = folderPrefix
    }
}

public struct SpaceMapNode: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let path: String?
    public let category: StorageCategory?
    public let allocatedBytes: Int64
    public let logicalBytes: Int64
    public let proportionOfAllocated: Double
    public let itemCount: Int
    public let isPartial: Bool
    public let partialReason: String?
    public let isZeroAllocatedSparse: Bool
    public let isOthersBucket: Bool
    public let groupedFileIDs: [String]
    public let indexedFile: IndexedFile?
    public let status: CategoryStatus?

    public init(
        id: String,
        title: String,
        subtitle: String,
        path: String? = nil,
        category: StorageCategory? = nil,
        allocatedBytes: Int64,
        logicalBytes: Int64,
        proportionOfAllocated: Double,
        itemCount: Int,
        isPartial: Bool,
        partialReason: String? = nil,
        isOthersBucket: Bool = false,
        groupedFileIDs: [String],
        indexedFile: IndexedFile? = nil,
        status: CategoryStatus? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.path = path
        self.category = category
        self.allocatedBytes = allocatedBytes
        self.logicalBytes = logicalBytes
        self.proportionOfAllocated = proportionOfAllocated
        self.itemCount = itemCount
        self.isPartial = isPartial
        self.partialReason = partialReason
        self.isZeroAllocatedSparse = (allocatedBytes == 0 && logicalBytes > 0)
        self.isOthersBucket = isOthersBucket
        self.groupedFileIDs = groupedFileIDs
        self.indexedFile = indexedFile
        self.status = status
    }
}

public struct SpaceMapSlice: Codable, Equatable, Sendable {
    public let scopeTitle: String
    public let breadcrumbs: [SpaceMapBreadcrumb]
    public let totalAllocatedBytes: Int64
    public let totalLogicalBytes: Int64
    public let totalItemCount: Int
    public let isPartial: Bool
    public let partialReasons: [String]
    public let tiles: [SpaceMapNode]
    public let equivalentList: [SpaceMapNode]

    public init(
        scopeTitle: String,
        breadcrumbs: [SpaceMapBreadcrumb],
        totalAllocatedBytes: Int64,
        totalLogicalBytes: Int64,
        totalItemCount: Int,
        isPartial: Bool,
        partialReasons: [String],
        tiles: [SpaceMapNode],
        equivalentList: [SpaceMapNode]
    ) {
        self.scopeTitle = scopeTitle
        self.breadcrumbs = breadcrumbs
        self.totalAllocatedBytes = totalAllocatedBytes
        self.totalLogicalBytes = totalLogicalBytes
        self.totalItemCount = totalItemCount
        self.isPartial = isPartial
        self.partialReasons = partialReasons
        self.tiles = tiles
        self.equivalentList = equivalentList
    }
}

public enum SpaceMapBuilder {
    /// Builds a Space Map slice directly from the active `ScanResult` without re-reading disk.
    /// Guarantees that `totalAllocatedBytes`, node `allocatedBytes`, and `groupedFileIDs` match the exact snapshot.
    /// Never substitutes `logicalBytes` when `allocatedBytes == 0`.
    public static func build(
        from scan: ScanResult,
        category: StorageCategory? = nil,
        folderPrefix rawFolderPrefix: String? = nil,
        maxVisibleTiles: Int = 8,
        language: String = "es",
        query: InventoryQuery? = nil,
        precomputedFilteredFiles: [IndexedFile]? = nil
    ) -> SpaceMapSlice {
        let sourceFiles: [IndexedFile] = if let precomputedFilteredFiles {
            precomputedFilteredFiles
        } else if let query {
            query.filterUnsorted(scan.files)
        } else {
            scan.files
        }
        let folderPrefix = rawFolderPrefix.map { Paths.normalized($0) }

        if category == nil && folderPrefix == nil {
            return buildCategoryOverview(
                from: scan,
                files: sourceFiles,
                maxVisibleTiles: maxVisibleTiles,
                language: language
            )
        }

        let matchingFiles: [IndexedFile]
        if category == nil && folderPrefix == nil {
            matchingFiles = sourceFiles
        } else {
            matchingFiles = sourceFiles.filter { file in
                if let cat = category, file.storageCategory != cat {
                    return false
                }
                if let prefix = folderPrefix {
                    guard SafetyPolicy.within(file.path, prefix) else {
                        return false
                    }
                }
                return true
            }
        }

        let totalAllocated = matchingFiles.reduce(Int64(0)) { ByteTotals.adding($0, $1.allocatedBytes) }
        let totalLogical = matchingFiles.reduce(Int64(0)) { ByteTotals.adding($0, $1.logicalBytes) }

        var reasons = coverageReasons(scan, language: language)
        var reasonSet = Set(reasons)
        var isPartial = !scan.complete && (scan.finishedAt != nil || !scan.files.isEmpty)
        if let cat = category,
           let report = scan.categories.first(where: { $0.category == cat }),
           (report.status == .partial || report.status == .noAccess) {
            isPartial = true
            let note = language == "es" ? report.statusNoteES : report.statusNoteEN
            if !note.isEmpty, reasonSet.insert(note).inserted {
                reasons.append(note)
            }
        }
        for file in matchingFiles where file.isPartial {
            isPartial = true
            if let reason = file.partialReason {
                let described = MeasurementNotes.describe(reason, language: language)
                if reasonSet.insert(described).inserted {
                    reasons.append(described)
                }
            }
        }

        let sortedFiles = matchingFiles.sorted {
            if $0.allocatedBytes != $1.allocatedBytes { return $0.allocatedBytes > $1.allocatedBytes }
            if $0.logicalBytes != $1.logicalBytes { return $0.logicalBytes > $1.logicalBytes }
            return $0.path < $1.path
        }

        var allNodes: [SpaceMapNode] = []
        allNodes.reserveCapacity(sortedFiles.count)
        for file in sortedFiles {
            let prop = totalAllocated > 0 ? Double(file.allocatedBytes) / Double(totalAllocated) : 0.0
            let name = Self.lastPathComponent(of: file.path)
            allNodes.append(
                SpaceMapNode(
                    id: file.id,
                    title: language == "es" ? (file.titleES.isEmpty ? name : file.titleES) : (file.titleEN.isEmpty ? name : file.titleEN),
                    subtitle: file.path,
                    path: file.path,
                    category: file.storageCategory,
                    allocatedBytes: file.allocatedBytes,
                    logicalBytes: file.logicalBytes,
                    proportionOfAllocated: prop,
                    itemCount: 1,
                    isPartial: file.isPartial,
                    partialReason: file.partialReason,
                    isOthersBucket: false,
                    groupedFileIDs: [file.id],
                    indexedFile: file,
                    status: file.isPartial ? .partial : .measured
                )
            )
        }

        let tiles = collapseIntoTiles(
            nodes: allNodes,
            totalAllocated: totalAllocated,
            maxVisibleTiles: maxVisibleTiles,
            scopeKey: category?.rawValue ?? folderPrefix ?? "root", language: language
        )
        let breadcrumbs = buildBreadcrumbs(category: category, folderPrefix: folderPrefix, language: language)
        let scopeTitle = breadcrumbs.last?.title ?? "Inventario"

        return SpaceMapSlice(
            scopeTitle: scopeTitle,
            breadcrumbs: breadcrumbs,
            totalAllocatedBytes: totalAllocated,
            totalLogicalBytes: totalLogical,
            totalItemCount: matchingFiles.count,
            isPartial: isPartial,
            partialReasons: reasons,
            tiles: tiles,
            equivalentList: allNodes
        )
    }

    private static func lastPathComponent(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        let next = path.index(after: slash)
        return next < path.endIndex ? String(path[next...]) : ""
    }

    private static func buildCategoryOverview(
        from scan: ScanResult,
        files: [IndexedFile],
        maxVisibleTiles: Int,
        language: String
    ) -> SpaceMapSlice {
        let filesByCategory = Dictionary(grouping: files, by: \.storageCategory)
        let reportsByCategory = Dictionary(scan.categories.map { ($0.category, $0) }, uniquingKeysWith: { first, _ in first })
        let totalAllocated = files.reduce(Int64(0)) { ByteTotals.adding($0, $1.allocatedBytes) }
        let totalLogical = files.reduce(Int64(0)) { ByteTotals.adding($0, $1.logicalBytes) }

        var isPartial = !scan.complete && (scan.finishedAt != nil || !files.isEmpty)
        var reasons = coverageReasons(scan, language: language)
        var reasonSet = Set(reasons)

        var categoryNodes: [SpaceMapNode] = []
        categoryNodes.reserveCapacity(StorageCategory.allCases.count)
        for cat in StorageCategory.allCases {
            let catFiles = filesByCategory[cat] ?? []
            let report = reportsByCategory[cat]
            let alloc = catFiles.reduce(Int64(0)) { ByteTotals.adding($0, $1.allocatedBytes) }
            let logic = catFiles.reduce(Int64(0)) { ByteTotals.adding($0, $1.logicalBytes) }
            let catPartial = (report?.status == .partial || report?.status == .noAccess) || catFiles.contains(where: \.isPartial)
            if catPartial {
                isPartial = true
                if let report {
                    let note = language == "es" ? report.statusNoteES : report.statusNoteEN
                    let title = language == "es" ? cat.titleES : cat.titleEN
                    let fullReason = "\(title): \(note)"
                    if !note.isEmpty, reasonSet.insert(fullReason).inserted { reasons.append(fullReason) }
                }
            }
            let prop = totalAllocated > 0 ? Double(alloc) / Double(totalAllocated) : 0.0
            categoryNodes.append(
                SpaceMapNode(
                    id: "category:\(cat.rawValue)",
                    title: language == "es" ? cat.titleES : cat.titleEN,
                    subtitle: language == "es" ? (report?.statusNoteES ?? cat.aboutES) : (report?.statusNoteEN ?? cat.aboutEN),
                    path: nil,
                    category: cat,
                    allocatedBytes: alloc,
                    logicalBytes: logic,
                    proportionOfAllocated: prop,
                    itemCount: catFiles.count,
                    isPartial: catPartial,
                    partialReason: catPartial ? (language == "es" ? report?.statusNoteES : report?.statusNoteEN) : nil,
                    isOthersBucket: false,
                    groupedFileIDs: catFiles.map(\.id),
                    indexedFile: nil,
                    status: report?.status ?? (catFiles.isEmpty ? .empty : .measured)
                )
            )
        }

        let sortedNodes = categoryNodes.sorted {
            if $0.allocatedBytes != $1.allocatedBytes { return $0.allocatedBytes > $1.allocatedBytes }
            if $0.logicalBytes != $1.logicalBytes { return $0.logicalBytes > $1.logicalBytes }
            return $0.title < $1.title
        }

        let nonEmptyNodes = sortedNodes.filter { $0.itemCount > 0 || $0.allocatedBytes > 0 || $0.logicalBytes > 0 }
        let tiles = collapseIntoTiles(nodes: nonEmptyNodes, totalAllocated: totalAllocated, maxVisibleTiles: maxVisibleTiles, scopeKey: "categories", language: language)

        return SpaceMapSlice(
            scopeTitle: language == "es" ? "Inventario por categoría" : "Inventory by category",
            breadcrumbs: [SpaceMapBreadcrumb(id: "root", title: language == "es" ? "Inventario" : "Inventory")],
            totalAllocatedBytes: totalAllocated,
            totalLogicalBytes: totalLogical,
            totalItemCount: files.count,
            isPartial: isPartial,
            partialReasons: reasons,
            tiles: tiles,
            equivalentList: sortedNodes
        )
    }

    private static func collapseIntoTiles(
        nodes: [SpaceMapNode],
        totalAllocated: Int64,
        maxVisibleTiles: Int,
        scopeKey: String,
        language: String
    ) -> [SpaceMapNode] {
        let cap = max(2, maxVisibleTiles)
        guard nodes.count > cap else {
            return nodes
        }
        let headCount = cap - 1
        let head = Array(nodes.prefix(headCount))
        let tail = Array(nodes.dropFirst(headCount))

        let tailAllocated = tail.reduce(Int64(0)) { ByteTotals.adding($0, $1.allocatedBytes) }
        let tailLogical = tail.reduce(Int64(0)) { ByteTotals.adding($0, $1.logicalBytes) }
        let tailItemCount = tail.reduce(0) { $0 + $1.itemCount }
        let tailPartial = tail.contains(where: \.isPartial)
        let tailIDs = tail.flatMap(\.groupedFileIDs)
        let prop = totalAllocated > 0 ? Double(tailAllocated) / Double(totalAllocated) : 0.0

        let othersNode = SpaceMapNode(
            id: "others:\(scopeKey)",
            title: language == "es" ? "Otros (\(tailItemCount) elementos)" : "Others (\(tailItemCount) items)",
            subtitle: language == "es" ? "Agrupación del resto de elementos de menor tamaño en disco" : "Remaining smaller items grouped together",
            path: nil,
            category: tail.first?.category,
            allocatedBytes: tailAllocated,
            logicalBytes: tailLogical,
            proportionOfAllocated: prop,
            itemCount: tailItemCount,
            isPartial: tailPartial,
            partialReason: tailPartial ? (language == "es" ? "Uno o más elementos agrupados son parciales." : "One or more grouped items are partial.") : nil,
            isOthersBucket: true,
            groupedFileIDs: tailIDs,
            indexedFile: nil,
            status: tailPartial ? .partial : .measured
        )

        return head + [othersNode]
    }

    private static func coverageReasons(_ scan: ScanResult, language: String) -> [String] {
        var reasons: [String] = []
        if scan.cancelled { reasons.append(language == "es" ? "Análisis cancelado." : "Scan cancelled.") }
        if scan.isStale { reasons.append(language == "es" ? "Inventario pendiente de actualizar." : "Inventory needs refresh.") }
        reasons.append(contentsOf: scan.errors)
        if !scan.complete && reasons.isEmpty && (scan.finishedAt != nil || !scan.files.isEmpty) {
            reasons.append(language == "es" ? "Cobertura parcial; consulta los estados por categoría." : "Partial coverage; see category states.")
        }
        return reasons
    }

    private static func buildBreadcrumbs(category: StorageCategory?, folderPrefix: String?, language: String) -> [SpaceMapBreadcrumb] {
        var crumbs = [SpaceMapBreadcrumb(id: "root", title: language == "es" ? "Inventario" : "Inventory")]
        if let cat = category {
            crumbs.append(SpaceMapBreadcrumb(id: "cat:\(cat.rawValue)", title: language == "es" ? cat.titleES : cat.titleEN, category: cat, folderPrefix: nil))
        }
        if let prefix = folderPrefix {
            let name = URL(fileURLWithPath: prefix).lastPathComponent
            crumbs.append(SpaceMapBreadcrumb(id: "folder:\(prefix)", title: name.isEmpty ? prefix : name, category: category, folderPrefix: prefix))
        }
        return crumbs
    }
}
