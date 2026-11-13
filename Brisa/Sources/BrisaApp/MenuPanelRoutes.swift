import SwiftUI
import AppKit
import BrisaCore

/// Inline candidate reviewer opened by "Review (N)" in the menu bar popover.
/// Presents all eligible items across categories without auto-selecting them or opening another window.
struct MenuReviewCandidatesPanel: View {
    @ObservedObject var state: AppState
    @ObservedObject var tools: ToolsCoordinator
    @State private var expandedID: String?

    private var eligibleFiles: [IndexedFile] {
        state.sortedEligibleFiles
    }

    private var totalEligibleBytes: Int64 {
        state.reclaimableAllocatedBytes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.MenuBar.candidatesTitle)
                    .font(.system(size: 13, weight: .semibold))
                Text(L10n.MenuBar.candidatesSubtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Text("\(eligibleFiles.count) · \(Formatting.bytes(totalEligibleBytes))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.mint)
                Spacer()
                if state.selected.count < min(eligibleFiles.count, 100) {
                    Button(L10n.MenuBar.candidatesSelectAll) {
                        state.selectAllEligible(100)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .buttonStyle(.borderless)
                    .foregroundStyle(Palette.accent)
                    .disabled(state.operating || state.scanning || eligibleFiles.isEmpty)
                }
                if !state.selected.isEmpty {
                    Button(L10n.MenuBar.candidatesClear) {
                        state.clearSelection()
                    }
                    .font(.system(size: 10, weight: .medium))
                    .buttonStyle(.borderless)
                    .foregroundStyle(Palette.muted)
                    .disabled(state.operating || state.scanning)
                }
            }

            if eligibleFiles.isEmpty {
                EmptyPanel(
                    icon: "checkmark.seal",
                    title: L10n.MenuBar.emptyAllClearTitle,
                    detail: L10n.MenuBar.emptyAllClearSubtitle
                )
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 6) {
                        ForEach(eligibleFiles) { file in
                            MenuCandidateRow(
                                file: file,
                                selected: state.selected.contains(file.id),
                                expanded: expandedID == file.id,
                                actionsEnabled: !state.operating && !state.scanning,
                                showCategoryPill: true,
                                toggleSelection: { state.toggle(file) },
                                toggleExpand: { expandedID = expandedID == file.id ? nil : file.id },
                                revealInFinder: { tools.openInFinder(path: file.path) },
                                protectItem: { do { try state.addProtection(file.path) } catch { state.fail(error) } }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: .infinity)
            }

            Divider().overlay(Palette.line)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.Tools.selectedCount(state.selected.count, Formatting.bytes(state.selectedBytes)))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    Text(L10n.Findings.selectionHint)
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
                Button(L10n.MenuBar.candidatesReviewPlan) {
                    tools.prepareInventoryPlan(selectedFiles: state.selectedFiles, fromMenuBar: true)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(state.selected.isEmpty || state.operating || state.scanning)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

/// Concise expandable file row used inside menu bar review and category lists.
struct MenuCandidateRow: View {
    let file: IndexedFile
    let selected: Bool
    let expanded: Bool
    let actionsEnabled: Bool
    let showCategoryPill: Bool
    let toggleSelection: () -> Void
    let toggleExpand: () -> Void
    let revealInFinder: () -> Void
    let protectItem: () -> Void

    @State private var showTechnical = false

    var body: some View {
        let presentation = InventoryItemPresentation(file: file)
        rowBody(presentation)
    }

    @ViewBuilder
    private func rowBody(_ presentation: InventoryItemPresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if presentation.selectable {
                    Button(action: toggleSelection) {
                        Image(systemName: selected ? "checkmark.square.fill" : "square")
                            .font(.system(size: 13))
                            .foregroundStyle(selected ? Palette.accent : Palette.muted)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .disabled(!actionsEnabled)
                    .accessibilityLabel(L10n.Findings.rowSelectAccessibility(presentation.name))
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 18, height: 18)
                }

                Button(action: toggleExpand) {
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(presentation.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Palette.text)
                                .lineLimit(1)
                            HStack(spacing: 5) {
                                if showCategoryPill {
                                    Text(storageCategoryTitle(file.storageCategory))
                                        .font(.system(size: 9))
                                        .foregroundStyle(Palette.muted)
                                        .lineLimit(1)
                                    Text("·")
                                        .font(.system(size: 9))
                                        .foregroundStyle(Palette.muted)
                                }
                                Text(presentation.status.title)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(presentation.status.color)
                            }
                        }
                        Spacer(minLength: 4)
                        Text(presentation.size)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(file.allocatedBytes > 0 ? Palette.text : Palette.muted)
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text(presentation.explanation)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(file.path)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                        .textSelection(.enabled)
                        .lineLimit(3)

                    HStack(spacing: 8) {
                        Text(L10n.Findings.rowLastChange(file.modifiedAt.formatted(date: .abbreviated, time: .omitted)))
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.muted)
                        Spacer()
                        Button(L10n.Common.actionShowInFinder, action: revealInFinder)
                            .font(.system(size: 10))
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        if presentation.selectable {
                            Button(L10n.Common.actionProtect, action: protectItem)
                                .font(.system(size: 10))
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .disabled(!actionsEnabled)
                        }
                    }

                    DisclosureGroup(L10n.Tools.technicalDetails, isExpanded: $showTechnical) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.Findings.rowAllocatedSize(Formatting.bytes(file.allocatedBytes)))
                            Text(L10n.Findings.rowLogicalSize(Formatting.bytes(file.logicalBytes)))
                            Text(L10n.Findings.rowUsageInspection(file.usageState.status))
                            Text(L10n.Findings.rowRule(file.reason))
                        }
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                        .padding(.top, 2)
                    }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Palette.muted)
                }
                .padding(.leading, 26)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            selected ? Palette.accent.opacity(0.08) : Palette.surfaceFill,
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}

/// Inline view-only storage explorer inside the menu bar popover.
struct MenuExploreSpacePanel: View {
    @ObservedObject var state: AppState
    @ObservedObject var tools: ToolsCoordinator

    private var maxCategoryBytes: Int64 {
        max(1, state.categories.map(\.allocatedBytes).max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.MenuBar.exploreTitle)
                    .font(.system(size: 13, weight: .semibold))
                Text(L10n.MenuBar.exploreNote)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !state.scan.complete && state.scan.finishedAt != nil {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.amber)
                    Text(L10n.MenuBar.statusPartialWarning)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.amber)
                }
                .padding(7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
            }

            ScrollView(.vertical) {
                VStack(spacing: 5) {
                    ForEach(state.categories) { report in
                        MenuExploreCategoryRow(
                            report: report,
                            maxBytes: maxCategoryBytes,
                            onSelect: { tools.pushMenuRoute(.category(report.category)) }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }
}

private struct MenuExploreCategoryRow: View {
    let report: CategoryReport
    let maxBytes: Int64
    let onSelect: () -> Void

    private var fraction: Double {
        guard report.allocatedBytes > 0, maxBytes > 0 else { return 0 }
        return min(1.0, max(0.03, Double(report.allocatedBytes) / Double(maxBytes)))
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Image(systemName: report.category.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(report.eligibleCount > 0 ? Palette.mint : Palette.categoryIcon)
                        .frame(width: 16)
                    Text(storageCategoryTitle(report.category))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if report.eligibleCount > 0 {
                        Pill(text: "\(report.eligibleCount)", color: Palette.mint)
                    }
                    Text(report.allocatedBytes > 0 ? Formatting.bytes(report.allocatedBytes) : L10n.Common.stateNoItems)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(report.allocatedBytes > 0 ? Palette.text : Palette.muted)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                }
                if report.allocatedBytes > 0 {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Palette.surfaceStrong)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(report.eligibleCount > 0 ? Palette.mint.opacity(0.75) : Palette.accent.opacity(0.65))
                                .frame(width: proxy.size.width * fraction)
                        }
                    }
                    .frame(height: 3)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(Palette.surfaceFill, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("menu.category." + report.category.rawValue)
    }
}

/// Organized hub inside the menu bar separating everyday tasks (duplicates, apps)
/// from advanced developer tools (projects, package caches, Docker).
struct MenuToolsHubPanel: View {
    @ObservedObject var tools: ToolsCoordinator

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.MenuBar.toolsEverydaySection)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                    hubRow(
                        icon: "doc.on.doc",
                        color: Palette.cyan,
                        title: L10n.MenuBar.toolsDuplicatesShort,
                        subtitle: L10n.MenuBar.toolsDuplicatesDesc,
                        route: .toolDuplicates
                    )
                    hubRow(
                        icon: "app.dashed",
                        color: Palette.indigo,
                        title: L10n.MenuBar.toolsAppsShort,
                        subtitle: L10n.MenuBar.toolsAppsDesc,
                        route: .toolApps
                    )
                }

                Divider().overlay(Palette.line)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.MenuBar.toolsAdvancedSection)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                    hubRow(
                        icon: "hammer",
                        color: Palette.amber,
                        title: L10n.MenuBar.toolsProjectsShort,
                        subtitle: L10n.MenuBar.toolsProjectsDesc,
                        route: .toolProjects
                    )
                    hubRow(
                        icon: "shippingbox",
                        color: Palette.muted,
                        title: L10n.MenuBar.toolsPackagesShort,
                        subtitle: L10n.MenuBar.toolsPackagesDesc,
                        route: .toolPackages
                    )
                    hubRow(
                        icon: "cube",
                        color: Palette.muted,
                        title: L10n.MenuBar.toolsDockerShort,
                        subtitle: L10n.MenuBar.toolsDockerDesc,
                        route: .toolDocker
                    )
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: 360)
    }

    private func hubRow(icon: String, color: Color, title: String, subtitle: String, route: MenuPanelRoute) -> some View {
        Button {
            tools.pushMenuRoute(route)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(color)
                    .frame(width: 24, height: 24)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Palette.surfaceFill, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
