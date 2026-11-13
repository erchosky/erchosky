import SwiftUI
import BrisaCore

struct AppUninstallerDetailView: View {
    @ObservedObject var tools: ToolsCoordinator
    let applications: [ApplicationItem]
    let compact: Bool
    var embedsScrollView: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            if compact {
                compactAppPickerAndDetail
            } else {
                fullInspectorContent
            }
        }
        .padding(compact ? 12 : 0)
    }

    @ViewBuilder
    private var compactAppPickerAndDetail: some View {
        if let inspection = tools.inspectedApp {
            HStack {
                Text(inspection.app.name)
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Button(L10n.Tools.recheck) {
                    if let current = applications.first(where: { $0.url.path == inspection.app.bundlePath }) {
                        tools.inspectApplication(current)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button(L10n.Common.actionRemove) {
                    tools.inspectedApp = nil
                    tools.selectedAppID = nil
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10.5))
            }
            fullInspectorContent
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(applications.prefix(40)) { app in
                        Button {
                            tools.inspectApplication(app)
                        } label: {
                            HStack(spacing: 8) {
                                Text(app.name)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(Palette.text)
                                    .lineLimit(1)
                                Spacer()
                                if let bundleID = app.bundleID {
                                    Text(bundleID)
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundStyle(Palette.muted)
                                        .lineLimit(1)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Palette.muted)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Palette.surfaceFill))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var fullInspectorContent: some View {
        if tools.isInspectingApp {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L10n.Tools.working)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.muted)
            }
            .padding(12)
        } else if let inspection = tools.inspectedApp {
            VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                // Header metadata
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(inspection.app.name)
                            .font(.system(size: compact ? 13 : 15, weight: .semibold))
                            .foregroundStyle(Palette.text)
                        if let ver = inspection.app.shortVersion {
                            Pill(text: "v\(ver)", color: Palette.muted)
                        }
                        if inspection.app.isSystemProtected {
                            Pill(text: L10n.Tools.uninstallerSystemProtected, color: Palette.coral)
                        }
                        Spacer()
                        Text(Formatting.bytes(inspection.app.allocatedBytes))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    if inspection.app.bundleID != nil || inspection.app.teamID != nil {
                        DisclosureGroup(L10n.Tools.technicalDetails) {
                            VStack(alignment: .leading, spacing: 2) {
                                if let bid = inspection.app.bundleID {
                                    Text(bid)
                                }
                                if let team = inspection.app.teamID {
                                    Text("Team: \(team)")
                                }
                            }
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Palette.muted)
                            .padding(.top, 2)
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.muted)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surfaceFill))

                // Running process blocker (never auto-kills!)
                if inspection.isRunning {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(L10n.Tools.uninstallerRunningBlocker, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.amber)
                        HStack(spacing: 8) {
                            Button(L10n.Tools.uninstallerQuitApp) {
                                tools.quitRunningInspectedApp()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button(L10n.Tools.recheck) {
                                if let app = applications.first(where: { $0.url.path == inspection.app.bundlePath }) {
                                    tools.inspectApplication(app)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Palette.amber.opacity(0.10)))
                }

                if !inspection.app.isSystemProtected && !inspection.app.requiresPrivilegesToTrash {
                    Toggle(isOn: $tools.includeAppBundleInUninstall) {
                        Text(L10n.Tools.uninstallerIncludeAppBundle)
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .toggleStyle(.checkbox)
                }

                OptionalVerticalScroll(enabled: embedsScrollView, maxHeight: compact ? 230 : 340) {
                    VStack(alignment: .leading, spacing: 10) {
                        relatedTierSection(
                            title: L10n.Tools.uninstallerExclusive,
                            items: inspection.exclusiveItems,
                            accent: Palette.accent
                        )
                        relatedTierSection(
                            title: L10n.Tools.uninstallerShared,
                            items: inspection.possibleSharedItems,
                            accent: Palette.amber
                        )
                        relatedTierSection(
                            title: L10n.Tools.uninstallerUncertain,
                            items: inspection.uncertainItems,
                            accent: Palette.muted
                        )
                    }
                }

                HStack {
                    Spacer()
                    Button(L10n.Tools.uninstallerPlanAction) {
                        tools.prepareUninstallPlan(fromMenuBar: compact)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(compact ? .small : .regular)
                    .disabled(
                        inspection.app.isSystemProtected
                        || (!tools.includeAppBundleInUninstall && tools.selectedUninstallItemIDs.isEmpty)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func relatedTierSection(title: String, items: [AppRelatedItem], accent: Color) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(title) (\(items.count))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                ForEach(items) { item in
                    let isSelected = tools.selectedUninstallItemIDs.contains(item.id)
                    HStack(alignment: .top, spacing: 8) {
                        if item.requiresPrivileges {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.coral)
                                .padding(.top, 2)
                        } else {
                            Button {
                                tools.toggleUninstallItem(item)
                            } label: {
                                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(isSelected ? accent : Palette.muted)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(item.displayName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Palette.text)
                                Pill(text: L10n.Tools.uninstallerConfidence(item.confidence), color: accent)
                                if item.requiresPrivileges {
                                    Pill(text: L10n.Tools.uninstallerPrivileged, color: Palette.coral)
                                }
                            }
                            Text(L10n.bilingual(es: item.reasonES, en: item.reasonEN))
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.muted)
                            if !item.sharedWithApps.isEmpty {
                                Text(L10n.Tools.uninstallerSharedWith(item.sharedWithApps.joined(separator: ", ")))
                                    .font(.system(size: 10))
                                    .foregroundStyle(Palette.amber)
                            }
                            Text(item.path)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(Palette.muted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Formatting.bytes(item.allocatedBytes))
                                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                .monospacedDigit()
                            Button(L10n.Tools.showInFinder) {
                                tools.openInFinder(path: item.path)
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 9.5))
                        }
                    }
                    .padding(7)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Palette.surfaceFill))
                }
            }
        }
    }
}
