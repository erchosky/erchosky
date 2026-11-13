import SwiftUI
import BrisaCore

struct MenuTriStateCheckbox: View {
    let state: TriStateCheckmark
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if disabled {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted.opacity(0.7))
                        .frame(width: 16, height: 16)
                } else {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(state == .unchecked ? Color.clear : Palette.accent)
                        .frame(width: 14, height: 14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .strokeBorder(state == .unchecked ? Palette.muted.opacity(0.6) : Palette.accent, lineWidth: 1.2)
                        )
                    if state == .checked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(.white)
                    } else if state == .mixed {
                        Rectangle()
                            .fill(.white)
                            .frame(width: 7, height: 1.8)
                    }
                }
            }
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct MenuToolsQuickStrip: View {
    @ObservedObject var tools: ToolsCoordinator

    private let columns = [GridItem(.adaptive(minimum: 102), spacing: 6)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            toolChip(icon: "hammer", title: L10n.MenuBar.toolsProjectsShort, route: .toolProjects)
            toolChip(icon: "shippingbox", title: L10n.MenuBar.toolsPackagesShort, route: .toolPackages)
            toolChip(icon: "doc.on.doc", title: L10n.MenuBar.toolsDuplicatesShort, route: .toolDuplicates)
            toolChip(icon: "app.dashed", title: L10n.MenuBar.toolsAppsShort, route: .toolApps)
            toolChip(icon: "cube.box", title: L10n.MenuBar.toolsDockerShort, route: .toolDocker)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func toolChip(icon: String, title: String, route: MenuPanelRoute) -> some View {
        Button {
            tools.pushMenuRoute(route)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background(Palette.surfaceFill, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}

struct MenuCategoryInlineItems: View {
    @ObservedObject var state: AppState
    let category: StorageCategory
    let maxInlineItems: Int

    var body: some View {
        let items = state.files(in: category)
        let visible = Array(items.prefix(maxInlineItems))

        VStack(alignment: .leading, spacing: 2) {
            if items.isEmpty {
                Text(L10n.Common.stateNoItems)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
                    .padding(.leading, 32)
                    .padding(.vertical, 4)
            } else {
                ForEach(visible) { file in
                    MenuInlineItemRow(
                        file: file,
                        selected: state.selected.contains(file.id),
                        selectionDisabled: state.operating || state.scanning,
                        toggleSelection: { state.toggle(file) },
                        openInFinder: { state.tools.openInFinder(path: file.path) }
                    )
                }
                if items.count > visible.count {
                    Button {
                        state.tools.pushMenuRoute(.category(category))
                    } label: {
                        HStack(spacing: 4) {
                            Text(L10n.MenuBar.categoryExpandHint + " (\(items.count))")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Palette.accent)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8.5))
                                .foregroundStyle(Palette.accent)
                        }
                        .padding(.leading, 30)
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, 4)
    }
}

struct MenuInlineItemRow: View {
    let file: IndexedFile
    let selected: Bool
    let selectionDisabled: Bool
    let toggleSelection: () -> Void
    let openInFinder: () -> Void

    @State private var expanded = false

    var body: some View {
        let presentation = InventoryItemPresentation(file: file)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                if presentation.selectable {
                    MenuTriStateCheckbox(
                        state: selected ? .checked : .unchecked,
                        disabled: selectionDisabled,
                        action: toggleSelection
                    )
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 18, height: 18)
                }

                Button {
                    expanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(presentation.name)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(presentation.selectable ? Palette.text : Palette.muted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(presentation.status.title)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(presentation.status.color)
                        }
                        Spacer(minLength: 4)
                        Text(Formatting.bytes(file.allocatedBytes))
                            .font(.system(size: 10.5, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(presentation.selectable ? Palette.text : Palette.muted)
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.explanation)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(presentation.location)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .padding(.leading, 25)
            }
        }
        .padding(.leading, 22)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .contextMenu {
            Button(L10n.Common.actionShowInFinder, action: openInFinder)
        }
    }
}

struct MenuCategoryDetailPanel: View {
    @ObservedObject var state: AppState
    let category: StorageCategory
    @State private var expandedID: String?

    var body: some View {
        let items = state.files(in: category)
        let eligible = items.filter(\.isReviewable)
        let triState = state.categorySelectionState(category)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                CategoryGlyphBadge(category: category, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(storageCategoryTitle(category))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Text(L10n.MenuBar.categoryItemsCount(items.count, eligible: eligible.count))
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
                if !eligible.isEmpty {
                    Button(triState == .checked ? L10n.MenuBar.actionClearCategorySelection : L10n.MenuBar.actionSelectEligibleInCategory) {
                        state.toggleCategorySelection(category)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            if items.isEmpty {
                VStack(spacing: 6) {
                    Text(L10n.Common.stateNoItemsDetected)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(items) { file in
                            MenuCandidateRow(
                                file: file,
                                selected: state.selected.contains(file.id),
                                expanded: expandedID == file.id,
                                actionsEnabled: !state.operating && !state.scanning,
                                showCategoryPill: false,
                                toggleSelection: { state.toggle(file) },
                                toggleExpand: { expandedID = expandedID == file.id ? nil : file.id },
                                revealInFinder: { state.tools.openInFinder(path: file.path) },
                                protectItem: { do { try state.addProtection(file.path) } catch { state.fail(error) } }
                            )
                        }
                    }
                    .padding(10)
                }
            }
        }
    }
}
