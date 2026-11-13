import SwiftUI
import AppKit
import BrisaCore

struct AgentsView: View {
    @EnvironmentObject var state: AppState
    var embedded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: embedded ? 14 : 22) {
            if !embedded {
                SectionHeading(
                    eyebrow: "",
                    title: L10n.AppsAgents.agentsTitle,
                    subtitle: L10n.AppsAgents.agentsSubtitle
                )
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label(L10n.AppsAgents.agentsExecutionDisabled, systemImage: "lock.shield")
                        .font(.headline)
                        .foregroundStyle(Palette.amber)
                    Text(L10n.AppsAgents.agentsBody)
                        .font(.callout)
                        .foregroundStyle(Palette.muted)
                }
            }
            ForEach(state.agents) { agent in
                Card(padding: 16) {
                    HStack(spacing: 16) {
                        Image(systemName: "terminal").font(.title3).foregroundStyle(Palette.cyan)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(agent.name).font(.headline)
                            Text(agent.executable ?? L10n.AppsAgents.agentsNotFound)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Palette.muted)
                                .textSelection(.enabled)
                            Text(L10n.AppsAgents.agentsStatusLine)
                                .font(.caption2)
                                .foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Pill(
                            text: agent.executable == nil ? L10n.AppsAgents.agentsNotDetected : L10n.AppsAgents.agentsInstalledReadOnly,
                            icon: agent.executable == nil ? "minus.circle" : "eye",
                            color: agent.executable == nil ? Palette.muted : Palette.cyan
                        )
                    }
                }
            }
            Button(L10n.AppsAgents.agentsDetectAgain) { state.refreshAgents() }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label("MCP · " + L10n.AppsAgents.agentsMCPTitle, systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.headline)
                    Text(L10n.AppsAgents.agentsMCPDescription)
                        .font(.callout)
                        .foregroundStyle(Palette.muted)
                }
            }
        }
    }
}

private struct AppBundleIconView: View {
    let bundlePath: String
    let size: CGFloat
    @State private var loaded: NSImage?

    var body: some View {
        let image = loaded ?? AppIconCache.shared.cachedIcon(forBundlePath: bundlePath)
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.16)
                    .foregroundStyle(Palette.muted)
            }
        }
        .frame(width: size, height: size)
        .task(id: bundlePath) {
            loaded = nil
            if let cached = AppIconCache.shared.cachedIcon(forBundlePath: bundlePath) {
                loaded = cached
                return
            }
            loaded = await AppIconCache.shared.loadIcon(forBundlePath: bundlePath)
        }
    }
}

struct ApplicationsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ApplicationsContentView(state: state, tools: state.tools)
    }
}

private struct ApplicationsContentView: View {
    @ObservedObject var state: AppState
    @ObservedObject var tools: ToolsCoordinator
    @State private var search = ""
    @State private var chosen: ApplicationItem?
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionHeading(
                eyebrow: "",
                title: L10n.AppsAgents.appsTitle,
                subtitle: L10n.AppsAgents.appsSubtitleUninstaller
            )
            TextField(L10n.AppsAgents.appsSearchPlaceholder, text: $search)
                .textFieldStyle(.roundedBorder)
            if state.applicationsScanIncomplete {
                Text(L10n.AppsAgents.appsPartialList)
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            if let app = chosen {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            AppBundleIconView(bundlePath: app.url.path, size: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(app.name).font(.title3.bold())
                                Text(app.bundleID ?? "—").font(.caption).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            Button(L10n.Common.actionShowInFinder) {
                                NSWorkspace.shared.activateFileViewerSelecting([app.url])
                            }
                            .buttonStyle(.bordered)
                            Button(L10n.AppsAgents.appsClosePreview) {
                                chosen = nil
                                tools.inspectedApp = nil
                            }
                            .buttonStyle(.bordered)
                        }
                        Text(app.url.path).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                        Text(L10n.AppsAgents.appsUninstallNote)
                            .font(.callout)
                            .foregroundStyle(Palette.muted)
                        AppUninstallerDetailView(tools: tools, applications: state.applications, compact: false, embedsScrollView: false)
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260))], spacing: 12) {
                ForEach(state.applications.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { app in
                    Button {
                        chosen = app
                        tools.inspectApplication(app)
                    } label: {
                        HStack(spacing: 12) {
                            AppBundleIconView(bundlePath: app.url.path, size: 34)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(app.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Text(InventoryItemPresentation.compactPath(app.url.deletingLastPathComponent().path))
                                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
                        }
                        .padding(14)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
            }
        }
        .onAppear { state.loadApplications() }
        .sheet(isPresented: $tools.showMenuPlanSheetInWindow) {
            OperationPlanReviewView(tools: tools, compact: false)
                .frame(minWidth: 560, idealWidth: 620, minHeight: 460)
        }
    }
}

struct ActivityView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let summary = state.journalSummary
        VStack(alignment: .leading, spacing: 22) {
            SectionHeading(
                eyebrow: "",
                title: L10n.Activity.title,
                subtitle: L10n.Activity.subtitle
            )

            if !state.journalEntries.isEmpty || !state.selected.isEmpty {
            Card(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        accountingMetric(
                            title: L10n.Activity.cardSelectionTitle,
                            value: Formatting.bytes(state.selectedBytes),
                            detail: L10n.Activity.cardSelectionDetail(state.selected.count),
                            color: Palette.cyan
                        )
                        accountingMetric(
                            title: L10n.Activity.cardTrashedTitle,
                            value: Formatting.bytes(summary.trashedBytes),
                            detail: L10n.Activity.cardTrashedDetail(summary.trashedCount),
                            color: Palette.mint
                        )
                        accountingMetric(
                            title: L10n.Activity.cardRestoredTitle,
                            value: Formatting.bytes(summary.restoredBytes),
                            detail: L10n.Activity.cardRestoredDetail(summary.restoredCount),
                            color: Palette.cyan
                        )
                        accountingMetric(
                            title: L10n.Activity.cardRejectedTitle,
                            value: Formatting.bytes(summary.rejectedBytes),
                            detail: L10n.Activity.cardRejectedDetail(summary.rejectedCount),
                            color: Palette.amber
                        )
                        accountingMetric(
                            title: L10n.Activity.cardDeltaTitle,
                            value: summary.latestFreeSpaceDelta.map { ($0 >= 0 ? "+" : "") + Formatting.bytes($0) } ?? "—",
                            detail: L10n.Activity.cardDeltaDetail,
                            color: Palette.muted
                        )
                        accountingMetric(
                            title: L10n.Activity.cardOutcomesTitle,
                            value: "\(summary.plannedCount + summary.completedPlansCount + summary.partialOrFailedCount)",
                            detail: L10n.Activity.cardOutcomesDetail(summary.plannedCount, summary.completedPlansCount, summary.partialOrFailedCount),
                            color: Palette.accent
                        )
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Palette.cyan)
                        Text(L10n.Activity.apfsNote)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.muted)
                    }
                }
            }

            }
            if !state.scan.errors.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        DisclosureGroup(L10n.Activity.sectionLastScan) {
                            ForEach(Array(Set(state.scan.errors)).sorted(), id: \.self) {
                                Text($0).font(.caption).textSelection(.enabled)
                            }.padding(.top, 8)
                        }.font(.system(size: 12))
                    }
                }
            }

            if state.journalEntries.isEmpty {
                Card {
                    EmptyPanel(
                        icon: "clock.arrow.circlepath",
                        title: L10n.Activity.emptyTitle,
                        detail: L10n.Activity.emptyDetail
                    )
                }
            }

            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(state.journalEntries) { entry in
                let isPlanEntry = entry.id.hasPrefix("plan-")
                let displayStatus = (!isPlanEntry && (entry.status == "trashed" || entry.status == "restored"))
                    ? entry.status
                    : (entry.outcomeKind ?? entry.status)
                let useEnglish = L10n.activeLanguage == .en
                let localizedTitle = useEnglish ? entry.summaryTitle : (entry.summaryTitleES ?? entry.summaryTitle)
                let localizedNote = useEnglish ? entry.detailNote : (entry.detailNoteES ?? entry.detailNote)
                Card(padding: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Pill(
                                text: journalStatusLabel(displayStatus),
                                icon: displayStatus == "trashed" ? "trash.fill" : (displayStatus == "restored" ? "arrow.uturn.backward.circle.fill" : (displayStatus == "completed" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")),
                                color: (displayStatus == "rejected" || displayStatus == "cancelled" || displayStatus == "failed" || displayStatus == "partial") ? Palette.amber : ((displayStatus == "trashed" || displayStatus == "completed") ? Palette.mint : Palette.cyan)
                            )
                            if let mech = entry.mechanism {
                                Pill(text: L10n.Activity.entryMechanism(mech), color: Palette.muted)
                            }
                            if let restorable = entry.restorable {
                                Pill(
                                    text: restorable ? L10n.Activity.entryRestorableYes : L10n.Activity.entryRestorableNo,
                                    color: restorable ? Palette.mint : Palette.coral
                                )
                            }
                            Text(L10n.Activity.entryLogical(Formatting.bytes(entry.size)))
                                .font(.caption.monospaced())
                            if let alloc = entry.allocatedBytes {
                                Text("· " + L10n.Activity.entryAllocated(Formatting.bytes(alloc)))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(Palette.cyan)
                            }
                            if let delta = entry.freeSpaceDelta {
                                Text("· " + L10n.Activity.entryDelta((delta >= 0 ? "+" : "") + Formatting.bytes(delta)))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                        }
                        if let title = localizedTitle, !title.isEmpty {
                            Text(title)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text(entry.originalPath)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                        if let domain = entry.domain,
                           let completed = entry.completedCount,
                           let skipped = entry.skippedOrFailedCount {
                            Text("\(L10n.Activity.entryDomain(domain)) · \(L10n.Activity.entryCounts(completed, skipped))")
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                        }
                        if let note = localizedNote, !note.isEmpty {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                        }
                        if let tr = entry.trashPath {
                            Text(L10n.Activity.entryTrashPath(tr))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Palette.muted)
                                .textSelection(.enabled)
                        }
                        if let error = entry.error {
                            Text(error).font(.caption).foregroundStyle(Palette.amber)
                        }
                        HStack {
                            Text("ID: \(entry.id)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Palette.muted)
                                .textSelection(.enabled)
                            Spacer()
                            if entry.status == "trashed" {
                                Button(L10n.Activity.entryReviewRestore) {
                                    Task { do { _ = try await state.undo(entry.id) } catch { state.fail(error) } }
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                                .disabled(state.operating || state.scanning)
                            }
                        }
                    }
                }
            }
            }

            DisclosureGroup(L10n.Activity.sectionScanActivity) {
            ForEach(state.activity) { entry in
                HStack(alignment: .top, spacing: 15) {
                    Text(entry.date, style: .time)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 70, alignment: .leading)
                    Text(entry.message)
                        .font(.system(size: 11))
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding(.vertical, 5)
            }
            }
        }
    }

    private func accountingMetric(title: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.muted)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LocationAccessTaskKey: Equatable {
    let inventoryRoots: [String]
    let protectedPaths: [String]
    let authorizedPromptRoots: [String]
}

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var locationAccessStates: [String: LocationAccessState] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionHeading(
                eyebrow: L10n.Settings.eyebrow,
                title: L10n.Settings.title,
                subtitle: L10n.Settings.subtitle
            )

            // 1. Language, Appearance & Read-only Inventory Roots
            Card {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(L10n.Settings.languageTitle, systemImage: "globe").font(.headline)
                            Text(L10n.Settings.languageHint)
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Picker("", selection: $state.language) {
                            ForEach(AppLanguage.allCases) { lang in
                                Text(L10n.Settings.label(for: lang)).tag(lang.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 210)
                    }

                    Divider().overlay(Palette.line)

                    HStack {
                        Label(L10n.Settings.appearanceTitle, systemImage: "circle.lefthalf.filled").font(.headline)
                        Spacer()
                        Picker("", selection: $state.appearance) {
                            ForEach(AppAppearance.allCases) { mode in
                                Text(mode.title).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 240)
                        .accessibilityLabel(L10n.Settings.appearanceTitle)
                    }

                    Divider().overlay(Palette.line)

                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(L10n.Settings.menuBarFreeSpaceTitle, systemImage: "menubar.rectangle")
                                .font(.headline)
                            Text(L10n.Settings.menuBarFreeSpaceHint)
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Toggle("", isOn: $state.showMenuBarFreeSpace)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .accessibilityLabel(L10n.Settings.menuBarFreeSpaceTitle)
                            .accessibilityIdentifier("settings.menuBarFreeSpace")
                    }

                    Divider().overlay(Palette.line)

                    HStack {
                        Label(L10n.Settings.inventoryRootsTitle, systemImage: "eye")
                            .font(.headline)
                        Spacer()
                        Pill(text: L10n.Settings.inventoryRootsPill, icon: "lock.fill", color: Palette.cyan)
                    }
                    Text(L10n.Settings.inventoryRootsDescription)
                        .font(.caption)
                        .foregroundStyle(Palette.muted)

                    ForEach(state.preferences.inventoryRoots, id: \.self) { path in
                        let locState = locationAccessStates[path] ?? .unavailable
                        HStack(spacing: 10) {
                            Text(path)
                                .font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer()
                            Pill(
                                text: locationAccessLabel(locState),
                                icon: locationAccessIcon(locState),
                                color: locationAccessColor(locState)
                            )
                            if locState == .skippedInteractivePrompt {
                                Button(L10n.Common.actionAuthorizeFolder) { state.addInventoryRoot() }
                                    .disabled(state.operating || state.scanning)
                            }
                            Button {
                                state.removeInventoryRoot(path)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .disabled(state.operating || state.scanning)
                            .accessibilityLabel(L10n.Settings.inventoryRootsRemoveAccessibility(path))
                        }
                    }

                    Button(L10n.Settings.inventoryRootsAddButton) {
                        state.addInventoryRoot()
                    }
                    .disabled(state.operating || state.scanning)
                }
            }

            // 2. Reviewed Cleanup Roots
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label(L10n.Settings.cleanupRootsTitle, systemImage: "checkmark.shield")
                            .font(.headline)
                        Spacer()
                        Pill(text: L10n.Settings.cleanupRootsPill, icon: "shield.lefthalf.filled", color: Palette.mint)
                    }
                    Text(L10n.Settings.cleanupRootsDescription)
                        .font(.caption)
                        .foregroundStyle(Palette.muted)

                    ForEach(state.preferences.roots, id: \.self) { path in
                        HStack {
                            Text(path)
                                .font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer()
                            Button {
                                state.removeRoot(path)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .disabled(state.operating || state.scanning)
                            .accessibilityLabel(L10n.Settings.cleanupRootsRemoveAccessibility(path))
                        }
                    }
                    Button(L10n.Settings.cleanupRootsAddButton) {
                        state.addRoot()
                    }
                    .disabled(state.operating || state.scanning)
                }
            }

            // 3. Protections
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Label(L10n.Settings.exclusionsTitle, systemImage: "lock.shield")
                        .font(.headline)
                    ForEach(state.preferences.protectedPaths, id: \.self) { path in
                        HStack {
                            Text(path).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                            Spacer()
                            Button(L10n.Settings.exclusionsRemoveButton) {
                                Task { do { try await state.removeProtection(path) } catch { state.fail(error) } }
                            }
                            .disabled(state.operating || state.scanning)
                        }
                    }
                    if state.preferences.protectedPaths.isEmpty {
                        Text(L10n.Settings.exclusionsEmpty)
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                    }
                    Button(L10n.Settings.exclusionsAddButton) {
                        do { try state.addProtection() } catch { state.fail(error) }
                    }
                    .disabled(state.operating || state.scanning)
                    Text(L10n.Settings.exclusionsAlwaysProtected)
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
            }

            // 4. Honest Permissions & Privacy
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Label(L10n.Settings.privacyTitle, systemImage: "hand.raised")
                        .font(.headline)
                    Text(L10n.Settings.privacyDescription)
                        .font(.callout)
                        .foregroundStyle(Palette.muted)
                    Button(L10n.Settings.privacyOpenSystemSettings) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    }
                    Divider().overlay(Palette.line)
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.Settings.notificationsTitle).font(.callout)
                            Text(state.preferences.notifications ? L10n.Settings.notificationsEnabled : L10n.Settings.notificationsDisabled)
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Button(state.preferences.notifications ? L10n.Settings.notificationsDisableButton : L10n.Settings.notificationsEnableButton) {
                            if state.preferences.notifications {
                                state.preferences.notifications = false
                                do { try state.savePreferences() } catch { state.fail(error) }
                            } else {
                                Task { await state.notificationPermission() }
                            }
                        }
                    }
                }
            }

            // 5. Advanced: Local tools & MCP (collapsed by default)
            Card {
                DisclosureGroup(isExpanded: $state.showAdvancedSettings) {
                    AgentsView(embedded: true)
                        .padding(.top, 10)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "wrench.and.screwdriver")
                            .foregroundStyle(Palette.muted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.Settings.advancedTitle)
                                .font(.headline)
                            Text(L10n.Settings.advancedSubtitle)
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                        }
                    }
                }
                .accessibilityIdentifier("settings.advanced")
            }
        }
        .task(id: LocationAccessTaskKey(
            inventoryRoots: state.preferences.inventoryRoots,
            protectedPaths: state.preferences.protectedPaths,
            authorizedPromptRoots: state.authorizedPromptRootsList
        )) {
            let home = state.homePath
            let roots = state.preferences.inventoryRoots
            let protected = state.preferences.protectedPaths
            let authorized = state.authorizedPromptRootsList
            let computed = await Task.detached(priority: .utility) {
                let policy = ReadAuthorizationPolicy(
                    home: home,
                    projectRoots: roots,
                    protectedPaths: protected,
                    allowSystemLocations: true,
                    authorizedPromptRoots: authorized
                )
                var result: [String: LocationAccessState] = [:]
                result.reserveCapacity(roots.count)
                for path in roots {
                    result[path] = policy.locationAccessState(path)
                }
                return result
            }.value
            guard !Task.isCancelled else { return }
            locationAccessStates = computed
        }
    }

    private func locationAccessLabel(_ state: LocationAccessState) -> String {
        switch state {
        case .explicitlyAuthorized: return L10n.Settings.pathStateExplicitlyAuthorized
        case .accessible: return L10n.Settings.pathStateAccessible
        case .deniedPermission: return L10n.Settings.pathStateDenied
        case .skippedInteractivePrompt: return L10n.Settings.pathStateRequiresAuthorization
        case .forbiddenSensitive: return L10n.Settings.pathStateSensitiveBlocked
        case .missing: return L10n.Settings.pathStateMissing
        case .unavailable: return L10n.Settings.pathStateNotVerified
        }
    }

    private func locationAccessIcon(_ state: LocationAccessState) -> String {
        switch state {
        case .explicitlyAuthorized, .accessible: return "checkmark.circle"
        case .deniedPermission, .skippedInteractivePrompt: return "lock.fill"
        case .forbiddenSensitive: return "nosign"
        case .missing, .unavailable: return "questionmark.folder"
        }
    }

    private func locationAccessColor(_ state: LocationAccessState) -> Color {
        switch state {
        case .explicitlyAuthorized, .accessible: return Palette.cyan
        case .deniedPermission, .skippedInteractivePrompt, .forbiddenSensitive: return Palette.amber
        case .missing, .unavailable: return Palette.muted
        }
    }
}
