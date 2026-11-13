import SwiftUI
import AppKit
import BrisaCore

struct SpaceMapView: View {
    @EnvironmentObject var state: AppState
    var followsInventoryFilters = true
    var onInspectFile: ((IndexedFile) -> Void)? = nil
    @State private var showAccessibleList = false
    @State private var selectedNode: SpaceMapNode? = nil

    private var activeCategory: StorageCategory? {
        followsInventoryFilters ? StorageCategory(rawValue: state.category) : nil
    }

    private var slice: SpaceMapSlice {
        state.spaceMap(
            category: activeCategory,
            folderPrefix: followsInventoryFilters ? state.spaceMapFolderPrefix : nil,
            filtered: followsInventoryFilters
        )
    }

    var body: some View {
        let currentSlice = slice
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                // Header + Breadcrumbs + Mode Toggle
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "square.split.bottomrightquarter.fill")
                        .foregroundStyle(Palette.cyan)
                    Text(L10n.Overview.spaceMapTitle)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))

                    breadcrumbBar(currentSlice.breadcrumbs)

                    Spacer()

                    if currentSlice.isPartial {
                        Pill(
                            text: L10n.Overview.spaceMapPartialMap,
                            icon: "exclamationmark.triangle.fill",
                            color: Palette.amber
                        )
                    } else if state.scan.finishedAt != nil {
                        Pill(
                            text: L10n.Overview.spaceMapSyncedWithList,
                            icon: "checkmark.seal",
                            color: Palette.cyan
                        )
                    }

                    Button {
                        showAccessibleList.toggle()
                    } label: {
                        Label(
                            showAccessibleList ? L10n.Overview.spaceMapShowTiles : L10n.Overview.spaceMapAccessibleList,
                            systemImage: showAccessibleList ? "square.grid.2x2" : "list.bullet.rectangle"
                        )
                        .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // Totals and explanation
                HStack(spacing: 14) {
                    Text(
                        L10n.Overview.spaceMapAllocatedPrefix(
                            state.scan.finishedAt == nil ? L10n.Overview.spaceMapNotMeasured : honestAllocatedSummary(allocatedBytes: currentSlice.totalAllocatedBytes, logicalBytes: currentSlice.totalLogicalBytes)
                        )
                    )
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.cyan)

                    Text("·")
                        .foregroundStyle(Palette.muted)

                    Text(L10n.Overview.spaceMapLogicalPrefix(state.scan.finishedAt == nil ? "—" : Formatting.bytes(currentSlice.totalLogicalBytes)))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.muted)

                    Text("·")
                        .foregroundStyle(Palette.muted)

                    Text(L10n.Overview.spaceMapItemsLabel(currentSlice.totalItemCount))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.muted)

                    Spacer()

                    Text(L10n.Overview.spaceMapReadOnlyHint)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted)
                }

                if currentSlice.isPartial, !currentSlice.partialReasons.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.amber)
                        Text(L10n.Overview.spaceMapPartialCoverage(currentSlice.partialReasons.prefix(2).joined(separator: " · ")))
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.amber)
                            .lineLimit(1)
                    }
                }

                if currentSlice.tiles.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: state.scan.finishedAt == nil ? "clock" : "tray")
                            .foregroundStyle(Palette.muted)
                        Text(
                            state.scan.finishedAt == nil
                            ? L10n.Overview.spaceMapEmptyNeedsScan
                            : L10n.Overview.spaceMapEmptyScope
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                } else {
                    // Proportional stacked bar
                    proportionalRibbon(tiles: currentSlice.tiles)

                    if showAccessibleList {
                        accessibleEquivalentListView(nodes: currentSlice.equivalentList)
                    } else {
                        // Interactive tile grid
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                            ForEach(currentSlice.tiles) { node in
                                tileButton(node)
                            }
                        }
                    }

                    if let inspected = selectedNode {
                        inspectedNodeBanner(inspected)
                    }
                }
            }
        }
        .onChange(of: currentSlice) { _, updated in
            if let selectedNode {
                self.selectedNode = (updated.tiles + updated.equivalentList).first { $0.id == selectedNode.id }
            }
        }
    }

    private func breadcrumbBar(_ crumbs: [SpaceMapBreadcrumb]) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(crumbs.enumerated()), id: \.element.id) { index, crumb in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Palette.muted)
                }
                Button {
                    if crumb.id == "root" {
                        state.category = "all"
                        state.spaceMapFolderPrefix = nil
                        selectedNode = nil
                    } else if let cat = crumb.category, crumb.folderPrefix == nil {
                        state.category = cat.rawValue
                        state.spaceMapFolderPrefix = nil
                        selectedNode = nil
                    } else if let prefix = crumb.folderPrefix {
                        state.spaceMapFolderPrefix = prefix
                        selectedNode = nil
                    }
                } label: {
                    Text(crumb.title)
                        .font(.system(size: 11, weight: index == crumbs.count - 1 ? .semibold : .regular))
                        .foregroundStyle(index == crumbs.count - 1 ? Palette.cyan : Palette.muted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(index == crumbs.count - 1 ? Palette.surfaceStrong : Palette.surfaceFill, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func proportionalRibbon(tiles: [SpaceMapNode]) -> some View {
        GeometryReader { geo in
            let visible = tiles.filter { $0.allocatedBytes > 0 }
            let available = max(0, geo.size.width - CGFloat(max(0, visible.count - 1)) * 2)
            HStack(spacing: 2) {
                ForEach(visible) { node in
                    let width = available * CGFloat(max(0, min(1, node.proportionOfAllocated)))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(tileColor(for: node))
                        .frame(width: width)
                        .help("\(node.title): \(honestAllocatedSummary(allocatedBytes: node.allocatedBytes, logicalBytes: node.logicalBytes))")
                }
            }
        }
        .frame(height: 12)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }

    private func tileButton(_ node: SpaceMapNode) -> some View {
        let pct = Int((node.proportionOfAllocated * 100).rounded())
        let accent = tileColor(for: node)
        return Button {
            handleNodeTap(node)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: tileIcon(for: node))
                        .font(.system(size: 11))
                        .foregroundStyle(accent)
                    Text(node.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    if node.isPartial {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.amber)
                    }
                    Text("\(pct)%")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(honestAllocatedSummary(allocatedBytes: node.allocatedBytes, logicalBytes: node.logicalBytes))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(node.isZeroAllocatedSparse ? Palette.muted : Palette.text)
                    Spacer()
                    Text(L10n.Overview.spaceMapTileItems(node.itemCount))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                }

                if node.isZeroAllocatedSparse {
                    Text(L10n.Overview.spaceMapSparseNote)
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.amber)
                        .lineLimit(1)
                } else {
                    Text(node.subtitle.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surfaceFill, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(accent.opacity(0.32), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(node.title), \(honestAllocatedSummary(allocatedBytes: node.allocatedBytes, logicalBytes: node.logicalBytes)), \(pct)%")
    }

    private func accessibleEquivalentListView(nodes: [SpaceMapNode]) -> some View {
        LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(nodes) { node in
                HStack(spacing: 10) {
                    Image(systemName: tileIcon(for: node))
                        .foregroundStyle(tileColor(for: node))
                        .frame(width: 16)
                    Text(node.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    if node.isPartial {
                        Pill(text: L10n.Common.statePartial, icon: "exclamationmark.triangle.fill", color: Palette.amber)
                    }
                    Spacer()
                    Text(L10n.Overview.spaceMapAllocatedLabel(Formatting.bytes(node.allocatedBytes)))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    Text(L10n.Overview.spaceMapLogicalPrefix(Formatting.bytes(node.logicalBytes)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                    Button(L10n.Overview.spaceMapInspect) {
                        handleNodeTap(node)
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Palette.surfaceFill, in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    private func inspectedNodeBanner(_ node: SpaceMapNode) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass.circle.fill")
                .foregroundStyle(Palette.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.title)
                    .font(.system(size: 11, weight: .semibold))
                Text(
                    (node.path ?? node.subtitle) + " · " +
                    L10n.Overview.spaceMapAssignedLabel(Formatting.bytes(node.allocatedBytes)) +
                    " · " + L10n.Overview.spaceMapLogicalPrefix(Formatting.bytes(node.logicalBytes))
                )
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Palette.muted)
                .textSelection(.enabled)
            }
            Spacer()
            if let path = node.path {
                Button(L10n.Common.actionShowInFinder) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Button {
                selectedNode = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Palette.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Palette.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }

    private func handleNodeTap(_ node: SpaceMapNode) {
        if node.isOthersBucket {
            selectedNode = node
            return
        }
        if let cat = node.category, node.path == nil {
            if !followsInventoryFilters {
                state.openCategory(cat)
                selectedNode = nil
                return
            }
            state.category = cat.rawValue
            state.spaceMapFolderPrefix = nil
            selectedNode = nil
            return
        }
        selectedNode = node
        if let file = node.indexedFile {
            onInspectFile?(file)
        }
    }

    private func tileColor(for node: SpaceMapNode) -> Color {
        if node.isOthersBucket { return Palette.muted }
        if node.isPartial { return Palette.amber }
        if let file = node.indexedFile, file.isReviewable { return Palette.mint }
        if let cat = node.category { return storageCategoryColor(cat) }
        return Palette.cyan
    }

    private func tileIcon(for node: SpaceMapNode) -> String {
        if node.isOthersBucket { return "ellipsis.rectangle.fill" }
        if let cat = node.category, node.path == nil { return cat.icon }
        if node.indexedFile?.isDirectory == true { return "folder.fill" }
        return "doc.fill"
    }
}
