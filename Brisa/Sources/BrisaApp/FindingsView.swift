import SwiftUI
import AppKit
import BrisaCore

struct FindingsView: View {
    @EnvironmentObject var state: AppState
    @State private var expanded: String?
    @State private var categoryInfo: StorageCategory?
    @State private var showScanInfo = false
    @State private var showSpaceMap = false
    @State private var showFilters = false
    @State private var showContextualDetectors = true
    @State private var detectorDisplayLimit = 25

    var visibleCategories: [CategoryReport] {
        switch state.category {
        case "all", "eligible", "inventory", "cache", "log", "other":
            return state.categories
        default:
            return state.categories.filter { $0.category.rawValue == state.category }
        }
    }

    private var hasAdvancedFilters: Bool {
        state.sizeFilter != "all" || state.typeFilter != "all" || state.statusFilter != "all"
            || state.dateFilter != "all" || state.locationFilter != "all"
    }

    private var hasActiveFilters: Bool {
        !state.query.isEmpty
            || state.sizeFilter != "all"
            || state.typeFilter != "all"
            || state.statusFilter != "all"
            || state.dateFilter != "all"
            || state.locationFilter != "all"
            || state.spaceMapFolderPrefix != nil
    }

    private var headerSubtitle: String {
        switch state.cleanMode {
        case .candidates: return L10n.MenuBar.candidatesSubtitle
        case .explore: return L10n.Overview.tasksExploreDesc
        case .duplicates: return L10n.Overview.tasksDuplicatesDesc
        case .advanced: return L10n.Tools.subtitle
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack(alignment: .center, spacing: 12) {
                SectionHeading(
                    eyebrow: "",
                    title: L10n.Findings.title,
                    subtitle: headerSubtitle
                )
                if state.cleanMode == .explore {
                    Button {
                        showSpaceMap.toggle()
                    } label: {
                        Label(
                            showSpaceMap ? L10n.Findings.hideMap : L10n.Findings.showMap,
                            systemImage: "square.split.bottomrightquarter"
                        )
                        .padding(4)
                    }
                    .buttonStyle(.bordered)
                }

                if state.cleanMode == .candidates || state.cleanMode == .explore {
                    if state.scanning {
                        Button { state.cancel() } label: {
                            Label(L10n.Common.actionCancel, systemImage: "stop.circle").padding(4)
                        }.buttonStyle(.bordered)
                    } else {
                        Button {
                            do { try state.startScan() } catch { state.fail(error) }
                        } label: {
                            Label(L10n.Common.actionScan, systemImage: "arrow.triangle.2.circlepath").padding(4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.cyan)
                        .disabled(state.operating)
                    }
                }
            }

            cleanModeBar

            switch state.cleanMode {
            case .candidates:
                candidatesWorkspaceBody
            case .explore:
                exploreWorkspaceBody
            case .duplicates:
                ExactDuplicatesToolView(tools: state.tools, compact: false)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
            case .advanced:
                ToolsView(tools: state.tools, embedded: true)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .background(ToolsPlanSheetPresenter(tools: state.tools))
    }

    private var cleanModeBar: some View {
        HStack(spacing: 8) {
            cleanModeButton(
                mode: .candidates,
                icon: "sparkles",
                label: L10n.Findings.modeCandidates,
                badge: state.scan.finishedAt == nil ? nil : "\(state.eligibleFiles.count)",
                accent: Palette.mint
            )
            cleanModeButton(
                mode: .explore,
                icon: "externaldrive",
                label: L10n.Findings.modeExplore,
                badge: nil,
                accent: Palette.cyan
            )
            cleanModeButton(
                mode: .duplicates,
                icon: "square.on.square",
                label: L10n.Findings.modeDuplicates,
                badge: nil,
                accent: Palette.cyan
            )
            cleanModeButton(
                mode: .advanced,
                icon: "wrench.and.screwdriver",
                label: L10n.Findings.modeAdvanced,
                badge: nil,
                accent: Palette.muted
            )
            Spacer(minLength: 0)
        }
    }

    private func cleanModeButton(
        mode: CleanWorkspaceMode,
        icon: String,
        label: String,
        badge: String?,
        accent: Color
    ) -> some View {
        let active = state.cleanMode == mode
        return Button {
            switch mode {
            case .candidates:
                state.openCleanCandidates()
            case .explore:
                state.openExploreSpace()
            case .duplicates:
                state.openDuplicates()
            case .advanced:
                let tab: MainToolsTab = state.tools.activeToolsTab == .duplicates ? .projects : state.tools.activeToolsTab
                state.openAdvancedTools(tab)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(active ? accent : Palette.muted)
                Text(label)
                    .font(.system(size: 11.5, weight: active ? .semibold : .regular))
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Palette.surfaceStrong, in: Capsule())
                }
            }
            .foregroundStyle(active ? accent : Palette.text.opacity(0.88))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(active ? accent.opacity(0.14) : Palette.card, in: Capsule())
            .overlay(Capsule().stroke(active ? accent.opacity(0.45) : Palette.line))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("clean.mode." + mode.rawValue)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    @ViewBuilder
    private var candidatesWorkspaceBody: some View {
        let filtered = state.scan.finishedAt == nil ? nil : state.reviewableFilteredSummary

        Card(padding: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField(L10n.Findings.searchPlaceholder, text: $state.query)
                    .textFieldStyle(.plain)
                    .accessibilityLabel(L10n.Findings.searchAccessibility)
                if !state.query.isEmpty {
                    Button { state.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted)
                    }.buttonStyle(.plain)
                }
                Divider().frame(height: 16)
                Picker(L10n.Findings.sortLabel, selection: $state.sortOrder) {
                    Text(L10n.Findings.sortLargest).tag("allocated_desc")
                    Text(L10n.Findings.sortLogical).tag("logical_desc")
                    Text(L10n.Findings.sortNewest).tag("modified_desc")
                    Text(L10n.Findings.sortName).tag("name_asc")
                }
                .frame(width: 215)
            }
        }

        inventoryBannerRow(filtered: filtered, showSelectAll: true)

        if state.scan.finishedAt == nil {
            EmptyPanel(
                icon: state.scanning ? "hourglass" : "magnifyingglass",
                title: state.scanning ? L10n.Findings.emptyLookingTitle : L10n.Findings.emptyScanTitle,
                detail: state.scanning ? L10n.Findings.emptyLookingDetail : L10n.Findings.emptyScanDetail,
                useIllustration: !state.scanning
            )
        } else if let filtered, filtered.files.isEmpty {
            VStack(spacing: 12) {
                EmptyPanel(
                    icon: hasActiveFilters ? "magnifyingglass" : "checkmark.seal",
                    title: hasActiveFilters ? L10n.Findings.emptyMatchesTitle : L10n.Findings.emptyReviewableTitle,
                    detail: hasActiveFilters ? L10n.Findings.emptyMatchesDetail : L10n.MenuBar.emptyAllClearSubtitle
                )
                Button(L10n.Overview.tasksExploreTitle) {
                    state.openExploreSpace()
                }
                .buttonStyle(.bordered)
            }
        } else if let filtered {
            inventoryList(summary: filtered)
        }
    }

    @ViewBuilder
    private var exploreWorkspaceBody: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.fill")
                .font(.system(size: 12))
                .foregroundStyle(Palette.cyan)
            Text(L10n.Findings.exploreInventoryNotice)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Palette.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

        HStack(spacing: 8) {
            categoryFilterChip(id: "all", icon: "square.grid.2x2", label: L10n.Findings.filterAll,
                badge: state.scan.finishedAt == nil ? "—" : "\(state.scan.files.count)", accent: Palette.cyan)
            categoryFilterChip(id: "eligible", icon: "checkmark.circle.fill", label: L10n.Findings.filterReviewable,
                badge: state.scan.finishedAt == nil ? "—" : "\(state.eligibleFiles.count)", accent: Palette.mint)
            categoryFilterChip(id: "inventory", icon: "eye.fill", label: L10n.Findings.filterViewOnly,
                badge: state.scan.finishedAt == nil ? "—" : "\(max(0, state.scan.files.count - state.eligibleFiles.count))", accent: Palette.cyan)
            Spacer(minLength: 0)
            Menu {
                ForEach(state.categories) { report in
                    Button {
                        state.category = report.category.rawValue
                        state.spaceMapFolderPrefix = nil
                    } label: {
                        Label(storageCategoryTitle(report.category), systemImage: report.category.icon)
                    }
                }
            } label: {
                Text(StorageCategory(rawValue: state.category).map(storageCategoryTitle) ?? L10n.Findings.categoriesAll11)
                    .font(.system(size: 11)).lineLimit(1)
            }
            .frame(maxWidth: 220)
            .accessibilityLabel(L10n.Findings.categoriesChoose)
            .accessibilityIdentifier("inventory.categoryMenu")
            if let category = StorageCategory(rawValue: state.category),
               let report = state.categories.first(where: { $0.category == category }) {
                Button { categoryInfo = category } label: {
                    Image(systemName: "info.circle").foregroundStyle(Palette.muted)
                }.buttonStyle(.plain)
                .accessibilityLabel(L10n.Common.aboutCategory(storageCategoryTitle(category)))
                .popover(isPresented: Binding(get: { categoryInfo == category }, set: { if !$0 { categoryInfo = nil } })) {
                    CategoryExplanationView(report: report)
                }
            }
        }

        if showSpaceMap {
            SpaceMapView { inspectedFile in
                expanded = inspectedFile.id
            }
        }

        // Search, Filter & Sort Panel
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                    TextField(
                        L10n.Findings.searchPlaceholder,
                        text: $state.query
                    )
                    .textFieldStyle(.plain)
                    .accessibilityLabel(L10n.Findings.searchAccessibility)

                    if !state.query.isEmpty {
                        Button { state.query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted)
                        }.buttonStyle(.plain)
                    }

                    Button { showFilters.toggle() } label: {
                        Label(L10n.Findings.filtersLabel, systemImage: hasAdvancedFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }.buttonStyle(.bordered).accessibilityIdentifier("inventory.filters")
                    Divider().frame(height: 16)

                    Picker(L10n.Findings.sortLabel, selection: $state.sortOrder) {
                        Text(L10n.Findings.sortLargest).tag("allocated_desc")
                        Text(L10n.Findings.sortLogical).tag("logical_desc")
                        Text(L10n.Findings.sortNewest).tag("modified_desc")
                        Text(L10n.Findings.sortName).tag("name_asc")
                    }
                    .frame(width: 215)
                }

                if showFilters || hasAdvancedFilters {
                    Divider().overlay(Palette.line)

                    // Multi-facet filters (Size, Type, Status, Date, Location)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], alignment: .leading, spacing: 10) {
                        Picker(L10n.Findings.filterSize, selection: $state.sizeFilter) {
                            Text(L10n.Findings.filterSizeAll).tag("all")
                            Text(L10n.Findings.filterSizeGt10MB).tag("gt10m")
                            Text(L10n.Findings.filterSizeGt100MB).tag("gt100m")
                            Text(L10n.Findings.filterSizeGt1GB).tag("gt1g")
                            Text(L10n.Findings.filterSizeSparse).tag("zero_allocated")
                        }
                        .frame(maxWidth: 185)

                        Picker(L10n.Findings.filterType, selection: $state.typeFilter) {
                            Text(L10n.Findings.filterTypeAll).tag("all")
                            Text(L10n.Findings.filterTypeRegular).tag("file")
                            Text(L10n.Findings.filterTypeDirs).tag("directory")
                        }
                        .frame(maxWidth: 175)

                        Picker(L10n.Findings.filterStatus, selection: $state.statusFilter) {
                            Text(L10n.Findings.filterStatusAll).tag("all")
                            Text(L10n.Findings.filterStatusEligible).tag("eligible")
                            Text(L10n.Findings.filterStatusInventory).tag("inventory")
                            Text(L10n.Findings.filterStatusInUse).tag("in_use")
                            Text(L10n.Findings.filterStatusPartial).tag("partial")
                        }
                        .frame(maxWidth: 185)

                        Picker(L10n.Findings.filterAge, selection: $state.dateFilter) {
                            Text(L10n.Findings.filterAgeAll).tag("all")
                            Text(L10n.Findings.filterAgeRecent).tag("lt24h")
                            Text(L10n.Findings.filterAgeGt7d).tag("gt7d")
                            Text(L10n.Findings.filterAgeGt30d).tag("gt30d")
                        }
                        .frame(maxWidth: 155)

                        Picker(L10n.Findings.filterLocation, selection: $state.locationFilter) {
                            Text(L10n.Findings.filterLocationAll).tag("all")
                            Text("~/Library").tag("library")
                            Text(L10n.Findings.filterLocationHidden).tag("hidden")
                            Text(L10n.Findings.filterLocationRoots).tag("projects")
                        }
                        .frame(maxWidth: 175)

                        if hasActiveFilters {
                            Button(L10n.Findings.filtersReset) {
                                state.resetFilters()
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .controlSize(.small)
                }
            }
        }

        let filtered = state.scan.finishedAt == nil ? nil : state.filteredSummary

        inventoryBannerRow(filtered: filtered, showSelectAll: true)

        if state.scan.finishedAt == nil {
            EmptyPanel(icon: state.scanning ? "hourglass" : "magnifyingglass",
                title: state.scanning ? L10n.Findings.emptyLookingTitle : L10n.Findings.emptyScanTitle,
                detail: state.scanning ? L10n.Findings.emptyLookingDetail : L10n.Findings.emptyScanDetail,
                useIllustration: !state.scanning)
        } else if let filtered, filtered.files.isEmpty && (hasActiveFilters || ["eligible", "inventory"].contains(state.category)) {
            EmptyPanel(icon: "magnifyingglass",
                title: state.category == "eligible" ? L10n.Findings.emptyReviewableTitle : L10n.Findings.emptyMatchesTitle,
                detail: L10n.Findings.emptyMatchesDetail)
        } else if let filtered {
            inventoryList(summary: filtered)
        }

        // Contextual Detectors Section (Orphaned Builds & Worktrees / Project Artifacts)
        if state.category == "all" || state.category == "inventory" || state.category == StorageCategory.developerCaches.rawValue {
            DisclosureGroup(L10n.Findings.detectorProjectsAndBuilds) {
                contextualDetectorsPanel.padding(.top, 10)
            }.font(.system(size: 12, weight: .medium))
        }

        if !state.conclusions.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label(L10n.Findings.detectorConclusionsTitle, systemImage: "sparkles")
                        .font(.headline)
                    ForEach(Array(state.conclusions.enumerated()), id: \.offset) { _, c in
                        Text(c.explanation).font(.caption).textSelection(.enabled)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func inventoryBannerRow(filtered: AppState.FilteredInventorySummary?, showSelectAll: Bool) -> some View {
        HStack(spacing: 10) {
            if state.scanning {
                ProgressView().controlSize(.small)
                Text(L10n.Findings.bannerScanning)
            } else if let filtered {
                let count = filtered.files.count
                let sizeStr = (filtered.hasPartial ? "≥ " : "") + Formatting.bytes(filtered.allocated)
                Text(L10n.Findings.bannerCountAllocated(L10n.Common.itemCount(count), sizeStr))
            }
            Spacer()
            if state.scan.finishedAt != nil && !state.scanning && !state.scan.complete {
                Button { showScanInfo.toggle() } label: {
                    Label(L10n.Findings.partialIncompleteScan, systemImage: "info.circle")
                }
                .buttonStyle(.plain).foregroundStyle(Palette.muted)
                .popover(isPresented: $showScanInfo) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.Findings.partialBodyTitle).font(.headline)
                        Text(L10n.Findings.partialBodyDetail)
                            .font(.callout).foregroundStyle(Palette.muted)
                    }.padding(20).frame(width: 340)
                }
            }
            if showSelectAll && filtered?.hasReviewable == true {
                Button(L10n.Findings.actionSelectReviewable) { state.selectVisible() }
                    .disabled(state.operating || state.scanning)
                    .help(L10n.Findings.actionSelectReviewableHelp)
            }
            if !state.selected.isEmpty {
                Button(L10n.Findings.actionClearSelection) {
                    do { try state.setSelection([]) } catch { state.fail(error) }
                }.disabled(state.operating)
            }
        }.font(.system(size: 11)).foregroundStyle(Palette.muted)
    }

    @ViewBuilder
    private func inventoryList(summary: AppState.FilteredInventorySummary) -> some View {
        let entries = flattenedListEntries(summary: summary)
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(entries) { entry in
                switch entry {
                case .header(let report, let count, let fullCategory, let topSpacing):
                    categoryHeaderRow(report: report, count: count, fullCategory: fullCategory)
                        .padding(.top, topSpacing)
                        .padding(.bottom, 10)
                case .empty(let report):
                    emptyCategoryRow(report)
                case .file(let file, let isFirst, let isLast):
                    fileCardRow(file, isFirst: isFirst, isLast: isLast)
                }
            }
        }
    }

    // MARK: - Category Filter Chip

    func categoryFilterChip(id: String, icon: String, label: String, badge: String, accent: Color) -> some View {
        let active = state.category == id
        return Button {
            state.category = id
            state.spaceMapFolderPrefix = nil
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11)).foregroundStyle(active ? accent : Palette.muted)
                Text(label).font(.system(size: 11, weight: active ? .semibold : .regular))
                Text(badge)
                    .font(.system(size: 9, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Palette.surfaceStrong, in: Capsule())
            }
            .foregroundStyle(active ? accent : Palette.text.opacity(0.88))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(active ? accent.opacity(0.14) : Palette.card, in: Capsule())
            .overlay(Capsule().stroke(active ? accent.opacity(0.45) : Palette.line))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label + ", " + badge)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: - Flattened Category Sections

    private enum FindingsListEntry: Identifiable {
        case header(CategoryReport, count: Int, fullCategory: Bool, topSpacing: CGFloat)
        case empty(CategoryReport)
        case file(IndexedFile, isFirst: Bool, isLast: Bool)

        var id: String {
            switch self {
            case .header(let report, _, _, _): return "header-\(report.id)"
            case .empty(let report): return "empty-\(report.id)"
            case .file(let file, _, _): return file.id
            }
        }
    }

    private func flattenedListEntries(summary: AppState.FilteredInventorySummary) -> [FindingsListEntry] {
        let activeFilters = hasActiveFilters
        var entries: [FindingsListEntry] = []
        var renderedFirstSection = false
        for report in visibleCategories {
            let files = summary.byCategory[report.category] ?? []
            let showEmptySection = state.category == report.category.rawValue && !activeFilters
            guard !files.isEmpty || showEmptySection else { continue }
            let fullCategory = !activeFilters && ["all", report.category.rawValue].contains(state.category)
            if state.category != report.category.rawValue {
                entries.append(
                    .header(
                        report,
                        count: files.count,
                        fullCategory: fullCategory,
                        topSpacing: renderedFirstSection ? 22 : 0
                    )
                )
            }
            renderedFirstSection = true
            if files.isEmpty {
                entries.append(.empty(report))
            } else {
                let lastIndex = files.count - 1
                for index in files.indices {
                    entries.append(.file(files[index], isFirst: index == 0, isLast: index == lastIndex))
                }
            }
        }
        return entries
    }

    private func categoryHeaderRow(report: CategoryReport, count: Int, fullCategory: Bool) -> some View {
        HStack(spacing: 8) {
            Text(storageCategoryTitle(report.category)).font(.system(size: 13, weight: .semibold))
            Text("\(count)").font(.system(size: 10)).foregroundStyle(Palette.muted)
            Button { categoryInfo = report.category } label: {
                Image(systemName: "info.circle").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Common.aboutCategory(storageCategoryTitle(report.category)))
            .popover(isPresented: Binding(get: { categoryInfo == report.category }, set: { if !$0 { categoryInfo = nil } })) {
                CategoryExplanationView(report: report)
            }
            Spacer()
            if fullCategory && (report.status == .measured || report.status == .partial && report.itemCount > 0) {
                Text((report.status == .partial ? "≥ " : "") + Formatting.bytes(report.allocatedBytes))
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(Palette.muted)
                    .help(L10n.Findings.categoryMeasuredSpace)
            }
        }
    }

    private func emptyCategoryRow(_ report: CategoryReport) -> some View {
        HStack(spacing: 12) {
            Text(emptyStateDescription(report)).font(.system(size: 11)).foregroundStyle(Palette.muted)
            Spacer()
            if report.status == .noAccess && report.category == .downloadsAndInstallers {
                Button(L10n.Common.actionAuthorizeFolder) {
                    state.addInventoryRoot(suggestedPath: state.homePath + "/Downloads")
                }.disabled(state.scanning || state.operating)
            }
        }.padding(16).background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func fileCardRow(_ file: IndexedFile, isFirst: Bool, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            fileRow(file)
            if !isLast {
                Divider().overlay(Palette.line.opacity(0.65))
            }
        }
        .background(
            Palette.card,
            in: UnevenRoundedRectangle(
                topLeadingRadius: isFirst ? 12 : 0,
                bottomLeadingRadius: isLast ? 12 : 0,
                bottomTrailingRadius: isLast ? 12 : 0,
                topTrailingRadius: isFirst ? 12 : 0
            )
        )
    }

    func emptyStateDescription(_ report: CategoryReport) -> String {
        switch report.status {
        case .pending:
            return L10n.Findings.categoryEmptyScan
        case .scanning:
            return L10n.Findings.categoryEmptyScanning
        case .notInstalled:
            return L10n.Findings.categoryEmptyNoFolders
        case .noAccess:
            return L10n.Findings.categoryEmptyNoAccess
        case .empty:
            return L10n.Findings.categoryEmptyCheckedEmpty
        case .partial:
            return L10n.Findings.categoryEmptyPartialFiltered
        case .measured:
            return L10n.Findings.categoryEmptyFiltered
        }
    }

    // MARK: - Progressive Disclosure File Row

    func fileRow(_ file: IndexedFile) -> some View {
        VStack(spacing: 0) {
            InventoryItemRow(file: file, selected: state.selected.contains(file.id),
                selectionEnabled: !state.operating && !state.scanning, expanded: expanded == file.id,
                toggleSelection: { state.toggle(file) },
                toggleDetails: { expanded = expanded == file.id ? nil : file.id })
            if expanded == file.id {
                InventoryItemDetails(file: file, actionsEnabled: !state.operating && !state.scanning,
                    reveal: { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)]) },
                    focusMap: { state.spaceMapFolderPrefix = file.path; showSpaceMap = true },
                    protect: { do { try state.addProtection(file.path) } catch { state.fail(error) } })
            }
        }.accessibilityElement(children: .contain)
    }

    // MARK: - Contextual Detectors Panel (Orphan Builds + Worktrees & Project Artifacts)

    private var contextualDetectorsPanel: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .foregroundStyle(Palette.cyan)
                    Text(L10n.Findings.detectorHeader)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Pill(text: L10n.Findings.detectorInventoryOnlyPill, icon: "eye", color: Palette.cyan)
                    Spacer()
                    Button(showContextualDetectors ? L10n.Findings.detectorCollapse : L10n.Findings.detectorExpand) {
                        showContextualDetectors.toggle()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if showContextualDetectors {
                    if max(state.orphanBuilds.count, state.worktrees.count, state.projectArtifacts.count) > detectorDisplayLimit {
                        HStack {
                            Text(L10n.Findings.detectorShowingUpTo(detectorDisplayLimit))
                                .font(.caption).foregroundStyle(Palette.muted)
                            Button(L10n.Findings.detectorShowMore25) { detectorDisplayLimit += 25 }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                    if state.contextualScanStatus != "measured" {
                        Text(state.scanning
                             ? L10n.Findings.detectorRunningOrPending
                             : state.contextualScanStatus == "pending"
                                ? L10n.Findings.detectorRunScanPrompt
                                : L10n.Findings.detectorPartialNote)
                            .font(.caption).foregroundStyle(Palette.amber)
                    }
                    // 1. Orphan Builds Detector
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L10n.Findings.detectorOrphansTitle)
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Text(L10n.Findings.detectorOrphansCount(state.orphanBuilds.count))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Palette.muted)
                        }

                        if state.orphanBuilds.isEmpty {
                            Text(L10n.Findings.detectorOrphansEmpty)
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                        } else {
                            ForEach(state.orphanBuilds.prefix(detectorDisplayLimit), id: \.buildPath) { item in
                                HStack(spacing: 10) {
                                    Image(systemName: orphanIcon(item.status))
                                        .foregroundStyle(orphanColor(item.status))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(URL(fileURLWithPath: item.buildPath).lastPathComponent)
                                            .font(.system(size: 11, weight: .medium))
                                        Text(L10n.bilingual(es: item.explanationES, en: item.explanationEN))
                                            .font(.system(size: 10))
                                            .foregroundStyle(Palette.muted)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Text(honestAllocatedSummary(allocatedBytes: item.allocatedBytes, logicalBytes: item.logicalBytes))
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    Pill(text: orphanBadgeText(item.status), color: orphanColor(item.status))
                                }
                                .padding(8)
                                .background(Palette.surfaceFill, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }

                    Divider().overlay(Palette.line)

                    // 2. Git Worktrees Detector
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L10n.Findings.detectorWorktreesTitle)
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Text(L10n.Findings.detectorWorktreesCount(state.worktrees.count))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Palette.muted)
                        }

                        if state.worktrees.isEmpty {
                            Text(L10n.Findings.detectorWorktreesEmpty)
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                        } else {
                            ForEach(state.worktrees.prefix(detectorDisplayLimit)) { wt in
                                HStack(spacing: 10) {
                                    Image(systemName: "point.3.connected.trianglepath.dotted")
                                        .foregroundStyle(worktreeColor(wt.status))
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(wt.worktreePath.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                                .lineLimit(1)
                                            Pill(text: wt.branchOrHead, color: Palette.cyan)
                                            if wt.isLinkedWorktree && !wt.isMainWorktree {
                                                Pill(text: L10n.Findings.detectorWorktreesLinked, color: Palette.indigo)
                                            }
                                        }
                                        Text(L10n.bilingual(es: wt.explanationES, en: wt.explanationEN))
                                            .font(.system(size: 10))
                                            .foregroundStyle(Palette.muted)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Text(honestAllocatedSummary(allocatedBytes: wt.allocatedBytes, logicalBytes: wt.logicalBytes))
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    Pill(text: worktreeStatusLabel(wt.status), color: worktreeColor(wt.status))
                                }
                                .padding(8)
                                .background(Palette.surfaceFill, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }

                    Divider().overlay(Palette.line)

                    // 3. Contextual Project Build Artifacts
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L10n.Findings.detectorArtifactsTitle)
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Text(L10n.Findings.detectorArtifactsCount(state.projectArtifacts.count))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Palette.muted)
                        }

                        if state.projectArtifacts.isEmpty {
                            Text(L10n.Findings.detectorArtifactsEmpty)
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                        } else {
                            ForEach(state.projectArtifacts.prefix(detectorDisplayLimit)) { art in
                                HStack(spacing: 10) {
                                    Image(systemName: "shippingbox.fill")
                                        .foregroundStyle(art.state == .anchoredIdleCandidate ? Palette.cyan : Palette.amber)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(art.artifactPath.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                                .lineLimit(1)
                                            Pill(text: "\(art.ecosystem) · \(art.anchorFile)", color: Palette.cyan)
                                        }
                                        Text(L10n.bilingual(es: art.explanationES, en: art.explanationEN))
                                            .font(.system(size: 10))
                                            .foregroundStyle(Palette.muted)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Text(honestAllocatedSummary(allocatedBytes: art.allocatedBytes, logicalBytes: art.logicalBytes))
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    Pill(
                                        text: art.state == .anchoredIdleCandidate ? L10n.Findings.detectorArtifactsAnchoredIdle : L10n.Findings.detectorArtifactsBlocked,
                                        color: art.state == .anchoredIdleCandidate ? Palette.cyan : Palette.amber
                                    )
                                }
                                .padding(8)
                                .background(Palette.surfaceFill, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
        }
    }

    private func orphanIcon(_ status: OrphanBuildStatus) -> String {
        switch status {
        case .activeProject: return "hammer.circle.fill"
        case .possiblyOrphaned: return "questionmark.folder.fill"
        case .missingMetadata, .invalidMetadata, .partial, .cancelled: return "exclamationmark.triangle.fill"
        case .permissionDenied: return "lock.shield.fill"
        case .unknownUnmountedVolume: return "externaldrive.badge.questionmark"
        }
    }

    private func orphanColor(_ status: OrphanBuildStatus) -> Color {
        switch status {
        case .activeProject: return Palette.cyan
        case .possiblyOrphaned, .missingMetadata, .invalidMetadata, .permissionDenied, .partial, .cancelled: return Palette.amber
        case .unknownUnmountedVolume: return Palette.muted
        }
    }

    private func orphanBadgeText(_ status: OrphanBuildStatus) -> String {
        switch status {
        case .activeProject: return L10n.Findings.orphanActiveProject
        case .partial: return L10n.Findings.orphanPartial
        case .cancelled: return L10n.Findings.orphanCancelled
        case .possiblyOrphaned: return L10n.Findings.orphanPossiblyOrphaned
        case .missingMetadata: return L10n.Findings.orphanMissingMetadata
        case .invalidMetadata: return L10n.Findings.orphanInvalidMetadata
        case .permissionDenied: return L10n.Findings.orphanPermissionDenied
        case .unknownUnmountedVolume: return L10n.Findings.orphanUnmountedVolume
        }
    }

    private func worktreeColor(_ status: WorktreeAuditStatus) -> Color {
        switch status {
        case .cleanIdle: return Palette.cyan
        case .dirtyUncommitted, .unpushedCommits, .locked, .inUseProcess, .inspectionFailedUnknown: return Palette.amber
        case .recentlyModified, .staleMissingDirectory: return Palette.muted
        }
    }
}

private struct ToolsPlanSheetPresenter: View {
    @ObservedObject var tools: ToolsCoordinator

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .sheet(isPresented: $tools.showMenuPlanSheetInWindow) {
                OperationPlanReviewView(tools: tools, compact: false)
                    .frame(minWidth: 560, idealWidth: 620, minHeight: 460)
            }
    }
}
