import SwiftUI
import BrisaCore

struct OptionalVerticalScroll<Content: View>: View {
    let enabled: Bool
    var maxHeight: CGFloat? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        if enabled {
            if let maxHeight {
                ScrollView(.vertical) {
                    content()
                }
                .frame(maxHeight: maxHeight)
            } else {
                ScrollView(.vertical) {
                    content()
                }
            }
        } else {
            content()
        }
    }
}

struct ToolsView: View {
    @ObservedObject var tools: ToolsCoordinator
    var embedded: Bool = false

    private let advancedTabs: [MainToolsTab] = [.projects, .packages, .docker]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header + Segmented tabs
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    if !embedded {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.Tools.title)
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                                .foregroundStyle(Palette.text)
                            Text(L10n.Tools.subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.muted)
                        }
                        Spacer()
                    }
                    Picker("", selection: $tools.activeToolsTab) {
                        ForEach(advancedTabs) { tab in
                            Text(tabTitle(tab)).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 420)
                    if embedded {
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, embedded ? 14 : 20)
            .padding(.bottom, 14)

            Divider()

            Group {
                switch tools.activeToolsTab {
                case .projects:
                    ProjectArtifactsToolView(tools: tools, compact: false, embedsScrollView: !embedded)
                case .packages:
                    PackageManagersToolView(tools: tools, compact: false, embedsScrollView: !embedded)
                case .duplicates:
                    ExactDuplicatesToolView(tools: tools, compact: false, embedsScrollView: !embedded)
                case .docker:
                    DockerToolView(tools: tools, compact: false, embedsScrollView: !embedded)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(embedded ? Color.clear : Palette.background)
        .onAppear {
            if tools.activeToolsTab == .duplicates {
                tools.activeToolsTab = .projects
            }
        }
        .sheet(isPresented: embedded ? .constant(false) : $tools.showMenuPlanSheetInWindow) {
            OperationPlanReviewView(tools: tools, compact: false)
                .frame(minWidth: 560, idealWidth: 620, minHeight: 460)
        }
    }

    private func tabTitle(_ tab: MainToolsTab) -> String {
        switch tab {
        case .projects: return L10n.Tools.tabProjects
        case .packages: return L10n.Tools.tabPackages
        case .duplicates: return L10n.Tools.tabDuplicates
        case .docker: return L10n.Tools.tabDocker
        }
    }
}

// MARK: - 1. Project Artifacts View

struct ProjectArtifactsToolView: View {
    @ObservedObject var tools: ToolsCoordinator
    let compact: Bool
    var embedsScrollView: Bool = true

    @MainActor private static var cachedFormatters: [String: DateFormatter] = [:]

    private static func formatter(for locale: Locale) -> DateFormatter {
        let key = locale.identifier
        if let existing = cachedFormatters[key] {
            return existing
        }
        let fmt = DateFormatter()
        fmt.locale = locale
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        cachedFormatters[key] = fmt
        return fmt
    }

    private var dateFormatter: DateFormatter {
        Self.formatter(for: L10n.locale)
    }

    var body: some View {
        let policy = tools.projectPolicy()
        let selectedBytes = tools.selectedProjectArtifactsSizeBytes()

        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            // Controls bar
            HStack(spacing: 8) {
                Button(L10n.Tools.projectsAddRoot) {
                    tools.chooseProjectRootFolder()
                }
                .buttonStyle(.bordered)
                .controlSize(compact ? .small : .regular)

                if tools.isScanningProjects {
                    ProgressView().controlSize(.small)
                    Button(L10n.Tools.cancel) { tools.cancelActiveWork() }
                        .buttonStyle(.bordered)
                        .controlSize(compact ? .small : .regular)
                } else {
                    Button(tools.projectGroups.isEmpty ? L10n.Tools.scan : L10n.Tools.rescan) {
                        tools.scanProjects()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(compact ? .small : .regular)
                }

                Spacer()

                if !tools.projectGroups.isEmpty {
                    Button(L10n.Tools.selectAllEligible) {
                        tools.selectAllEligibleProjectArtifacts()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: compact ? 10.5 : 11.5))

                    if !tools.selectedProjectArtifactIDs.isEmpty {
                        Button(L10n.Tools.clearSelection) {
                            tools.selectedProjectArtifactIDs.removeAll()
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: compact ? 10.5 : 11.5))
                    }
                }
            }

            if !compact {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.Tools.projectsSubtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                    Text(L10n.Tools.projectsUncertaintyNote)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.amber)
                }
            }

            if !tools.projectAuthorizedRoots.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tools.projectAuthorizedRoots, id: \.self) { root in
                            HStack(spacing: 4) {
                                Text(URL(fileURLWithPath: root).lastPathComponent)
                                    .font(.system(size: 10.5))
                                Button {
                                    tools.removeProjectRoot(root)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Palette.surfaceFill))
                        }
                    }
                }
            }

            if let err = tools.projectsError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.coral)
            }

            if tools.projectGroups.isEmpty {
                Spacer(minLength: 8)
                Text(L10n.Tools.projectsEmpty)
                    .font(.system(size: compact ? 11 : 12.5))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, compact ? 18 : 40)
                Spacer(minLength: 8)
            } else {
                OptionalVerticalScroll(enabled: embedsScrollView) {
                    LazyVStack(alignment: .leading, spacing: compact ? 6 : 10) {
                        ForEach(tools.projectGroups) { group in
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { tools.expandedProjectGroupIDs.contains(group.id) },
                                    set: { isOpen in
                                        if isOpen {
                                            tools.expandedProjectGroupIDs.insert(group.id)
                                        } else {
                                            tools.expandedProjectGroupIDs.remove(group.id)
                                        }
                                    }
                                )
                            ) {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(group.artifacts) { artifact in
                                        let decision = policy.evaluate(artifact)
                                        projectArtifactRow(artifact, decision: decision)
                                    }
                                }
                                .padding(.top, 6)
                            } label: {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(group.projectName)
                                                .font(.system(size: compact ? 11.5 : 13, weight: .semibold))
                                                .foregroundStyle(Palette.text)
                                            Pill(text: group.primaryEcosystem, color: Palette.accent)
                                        }
                                        Text(group.projectRoot)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(Palette.muted)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Spacer()
                                    Text(Formatting.bytes(group.totalAllocatedBytes))
                                        .font(.system(size: compact ? 11 : 12.5, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(Palette.text)
                                }
                            }
                            .padding(compact ? 8 : 12)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.card))
                        }
                    }
                }
            }

            if !tools.selectedProjectArtifactIDs.isEmpty {
                Divider()
                HStack {
                    Text(L10n.Tools.selectedCount(tools.selectedProjectArtifactIDs.count, Formatting.bytes(selectedBytes)))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.text)
                    Spacer()
                    Button(L10n.Tools.reviewPlan) {
                        tools.prepareProjectCleanupPlan(fromMenuBar: compact)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(compact ? .small : .regular)
                }
            }
        }
        .padding(compact ? 12 : 24)
    }

    @ViewBuilder
    private func projectArtifactRow(_ item: ProjectArtifactAuditEntry, decision: ProjectArtifactCleanupDecision) -> some View {
        let isSelected = tools.selectedProjectArtifactIDs.contains(item.id)
        HStack(alignment: .top, spacing: 8) {
            if decision.allowed {
                Button {
                    tools.toggleProjectArtifact(item, decision: decision)
                } label: {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 14))
                        .foregroundStyle(isSelected ? Palette.accent : Palette.muted)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.amber)
                    .padding(.top, 3)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.artifactName)
                        .font(.system(size: compact ? 11 : 12, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Text(item.ecosystem)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted)
                    Spacer()
                    Text(Formatting.bytes(item.allocatedBytes))
                        .font(.system(size: compact ? 11 : 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Text(L10n.bilingual(es: item.regenerableReasonES, en: item.regenerableReasonEN))
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
                if !decision.allowed,
                   let reasonES = decision.blockReasonES,
                   let reasonEN = decision.blockReasonEN {
                    Text(L10n.bilingual(es: reasonES, en: reasonEN))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.amber)
                }
                HStack {
                    Text(item.artifactPath)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(L10n.Tools.showInFinder) {
                        tools.openInFinder(path: item.artifactPath)
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10))
                }
                DisclosureGroup(L10n.Tools.technicalDetails) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.Tools.allocatedLogical(Formatting.bytes(item.allocatedBytes), Formatting.bytes(item.logicalBytes)))
                        if let date = item.latestChildModifiedAt ?? item.modifiedAt {
                            Text(L10n.Tools.modified(dateFormatter.string(from: date)))
                        }
                        Text("\(L10n.Tools.projectsRebuildLabel) \(item.rebuildCommand)")
                            .font(.system(size: 9.5, design: .monospaced))
                    }
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 2)
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Palette.muted)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.surfaceFill))
    }
}

// MARK: - 2. Package Managers View

struct PackageManagersToolView: View {
    @ObservedObject var tools: ToolsCoordinator
    let compact: Bool
    var embedsScrollView: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack {
                if tools.isScanningPackages {
                    ProgressView().controlSize(.small)
                    Button(L10n.Tools.cancel) { tools.cancelActiveWork() }
                        .buttonStyle(.bordered)
                        .controlSize(compact ? .small : .regular)
                } else {
                    Button(tools.packageInspections.isEmpty ? L10n.Tools.scan : L10n.Tools.rescan) {
                        tools.scanPackageManagers()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(compact ? .small : .regular)
                }
                Spacer()
            }

            if !compact {
                Text(L10n.Tools.packagesSubtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.muted)
            }

            if let err = tools.packagesError {
                Text(err).font(.system(size: 11)).foregroundStyle(Palette.coral)
            }

            OptionalVerticalScroll(enabled: embedsScrollView) {
                VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                    if tools.packageInspections.isEmpty {
                        Text(L10n.Tools.packagesEmpty)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(tools.packageInspections) { insp in
                            packageManagerCard(insp)
                        }
                    }
                }
            }
        }
        .padding(compact ? 12 : 24)
    }

    @ViewBuilder
    private func packageManagerCard(_ insp: PackageManagerInspection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(insp.displayName)
                            .font(.system(size: compact ? 12 : 14, weight: .semibold))
                            .foregroundStyle(Palette.text)
                        if insp.isInstalled {
                            Pill(
                                text: insp.variantLabel ?? L10n.Tools.packagesVersion(insp.versionString ?? "—"),
                                color: Palette.mint
                            )
                        } else {
                            Pill(text: L10n.Tools.packagesNotInstalled, color: Palette.muted)
                        }
                    }
                    if let firstCache = insp.cachePaths.first {
                        Text(L10n.Tools.packagesCachePath(firstCache))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                if let bytes = insp.cacheAllocatedBytes {
                    Text(Formatting.bytes(bytes))
                        .font(.system(size: compact ? 12 : 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.text)
                }
            }

            if insp.isInstalled {
                Text(L10n.bilingual(es: insp.preservedSummaryES, en: insp.preservedSummaryEN))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.mint)

                ForEach(insp.capabilities) { cap in
                    capabilityRow(insp: insp, cap: cap)
                }
            }
        }
        .padding(compact ? 10 : 14)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.card))
    }

    @ViewBuilder
    private func capabilityRow(insp: PackageManagerInspection, cap: PackageManagerOperationCapability) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if compact {
                Text(L10n.bilingual(es: cap.titleES, en: cap.titleEN))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    capabilityScopePill(cap.scope)
                    Spacer(minLength: 4)
                    capabilityActionControls(insp: insp, cap: cap, horizontal: true)
                }
                capabilityDetails(cap: cap)
            } else {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(L10n.bilingual(es: cap.titleES, en: cap.titleEN))
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(Palette.text)
                            capabilityScopePill(cap.scope)
                        }
                        capabilityDetails(cap: cap)
                    }
                    Spacer()
                    capabilityActionControls(insp: insp, cap: cap, horizontal: false)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.surfaceFill))
    }

    @ViewBuilder
    private func capabilityScopePill(_ scope: PackageManagerCacheScope) -> some View {
        if scope == .entireCache {
            Pill(text: L10n.Tools.packagesScopeWhole, color: Palette.amber)
        } else if scope == .unreferencedAndOutdated {
            Pill(text: L10n.Tools.packagesScopePartial, color: Palette.accent)
        }
    }

    @ViewBuilder
    private func capabilityDetails(cap: PackageManagerOperationCapability) -> some View {
        Text(L10n.bilingual(es: cap.descriptionES, en: cap.descriptionEN))
            .font(.system(size: 10.5))
            .foregroundStyle(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
        if cap.scope == .entireCache {
            Text(L10n.Tools.packagesWholeWarning)
                .font(.system(size: 10))
                .foregroundStyle(Palette.amber)
                .fixedSize(horizontal: false, vertical: true)
        }
        if !cap.isAvailable, let rES = cap.unavailableReasonES, let rEN = cap.unavailableReasonEN {
            Text(L10n.bilingual(es: rES, en: rEN))
                .font(.system(size: 10))
                .foregroundStyle(Palette.coral)
                .fixedSize(horizontal: false, vertical: true)
        }
        DisclosureGroup(L10n.Tools.technicalDetails) {
            Text(cap.commandPreview)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Palette.muted)
                .textSelection(.enabled)
                .padding(.top, 2)
        }
        .font(.system(size: 9.5, weight: .medium))
        .foregroundStyle(Palette.muted)
    }

    @ViewBuilder
    private func capabilityActionControls(insp: PackageManagerInspection, cap: PackageManagerOperationCapability, horizontal: Bool) -> some View {
        let sizeView = Group {
            if let est = cap.estimatedReclaimableBytes ?? cap.measuredCacheBytes {
                Text(Formatting.bytes(est))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        let buttonView = Button(L10n.Tools.reviewPlan) {
            tools.preparePackageManagerPlan(inspection: insp, capability: cap, fromMenuBar: compact)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(!cap.isAvailable || cap.scope == .unsupportedForGlobalCleanup)

        if horizontal {
            HStack(spacing: 8) { sizeView; buttonView }
        } else {
            VStack(alignment: .trailing, spacing: 4) { sizeView; buttonView }
        }
    }
}

// MARK: - 3. Exact Duplicates View

struct ExactDuplicatesToolView: View {
    @ObservedObject var tools: ToolsCoordinator
    let compact: Bool
    var embedsScrollView: Bool = true

    var body: some View {
        let totals = tools.duplicateSelectionTotals()

        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(spacing: 8) {
                Button(L10n.Tools.duplicatesChooseFolder) {
                    tools.chooseDuplicateFolder()
                }
                .buttonStyle(.bordered)
                .controlSize(compact ? .small : .regular)

                if tools.isScanningDuplicates {
                    ProgressView().controlSize(.small)
                    Button(L10n.Tools.cancel) { tools.cancelActiveWork() }
                        .buttonStyle(.bordered)
                        .controlSize(compact ? .small : .regular)
                } else {
                    Button(tools.duplicateReport == nil ? L10n.Tools.scan : L10n.Tools.rescan) {
                        tools.scanDuplicates()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(compact ? .small : .regular)
                    .disabled(tools.duplicateAuthorizedRoots.isEmpty)
                }

                Spacer()

                if let report = tools.duplicateReport, !report.groups.isEmpty {
                    Button(L10n.Tools.selectAllEligible) {
                        tools.selectSurplusCopiesForAllGroups()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10.5))
                }
            }

            if !compact {
                Text(L10n.Tools.duplicatesSubtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.muted)
            }

            if !tools.duplicateAuthorizedRoots.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tools.duplicateAuthorizedRoots, id: \.self) { root in
                            HStack(spacing: 4) {
                                Text(URL(fileURLWithPath: root).lastPathComponent)
                                    .font(.system(size: 10.5))
                                Button {
                                    tools.removeDuplicateFolder(root)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Palette.surfaceFill))
                        }
                    }
                }
            }

            if let prog = tools.duplicateProgress, tools.isScanningDuplicates {
                Text(L10n.Tools.duplicatesProgress(prog.visitedFiles, prog.sizeCandidateGroups, prog.hashedFiles))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.accent)
            }

            if let err = tools.duplicatesError {
                Text(err).font(.system(size: 11)).foregroundStyle(Palette.coral)
            }

            if let report = tools.duplicateReport {
                if report.groups.isEmpty {
                    Text(L10n.Common.stateNoItemsDetected)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .padding(.vertical, 20)
                } else {
                    Text(L10n.Tools.duplicatesGroups(report.groups.count))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                    OptionalVerticalScroll(enabled: embedsScrollView) {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(report.groups) { group in
                                duplicateGroupCard(group)
                            }
                        }
                    }
                }
            } else {
                Spacer(minLength: 8)
                Text(L10n.Tools.duplicatesEmpty)
                    .font(.system(size: compact ? 11 : 12.5))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, compact ? 18 : 36)
                Spacer(minLength: 8)
            }

            if totals.selectedBytes > 0 {
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.Tools.duplicatesReclaimableVsSelected(
                            Formatting.bytes(totals.selectedBytes),
                            Formatting.bytes(totals.reclaimableBytes)
                        ))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.text)
                    }
                    Spacer()
                    Button(L10n.Tools.reviewPlan) {
                        tools.prepareDuplicatesPlan(fromMenuBar: compact)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(compact ? .small : .regular)
                }
            }
        }
        .padding(compact ? 12 : 24)
    }

    @ViewBuilder
    private func duplicateGroupCard(_ group: DuplicateGroup) -> some View {
        let keptPath = tools.duplicateKeptCopyByGroup[group.id] ?? group.suggestedProtectedPath
        DisclosureGroup(
            isExpanded: Binding(
                get: { tools.expandedDuplicateGroupIDs.contains(group.id) },
                set: { open in
                    if open {
                        tools.expandedDuplicateGroupIDs.insert(group.id)
                    } else {
                        tools.expandedDuplicateGroupIDs.remove(group.id)
                    }
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 6) {
                if group.likelyContainsAPFSClones {
                    Text(L10n.Tools.duplicatesAPFSCloneNote)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.amber)
                }
                ForEach(group.files) { file in
                    let isKept = file.path == keptPath
                    let isChecked = tools.duplicateSelectedDeletePaths.contains(file.path)
                    HStack(alignment: .top, spacing: 8) {
                        if isKept {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.mint)
                                .padding(.top, 2)
                        } else {
                            Button {
                                tools.toggleDuplicateCopy(file, in: group)
                            } label: {
                                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 14))
                                    .foregroundStyle(isChecked ? Palette.accent : Palette.muted)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(file.fileName)
                                    .font(.system(size: 11, weight: .semibold))
                                if isKept {
                                    Pill(text: L10n.Tools.duplicatesProtectedCopy, color: Palette.mint)
                                }
                            }
                            Text(file.path)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(Palette.muted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            HStack(spacing: 8) {
                                Text(Formatting.bytes(file.allocatedBytes))
                                    .font(.system(size: 10, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.muted)
                                if !isKept {
                                    Button(L10n.Common.actionProtect) {
                                        tools.setProtectedCopy(for: group, path: file.path)
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.system(size: 10))
                                }
                                Button(L10n.Tools.showInFinder) {
                                    tools.openInFinder(path: file.path)
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 10))
                            }
                        }
                        Spacer()
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Palette.surfaceFill))
                }
                DisclosureGroup(L10n.Tools.technicalDetails) {
                    Text("SHA-256: \(group.sha256)")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                        .textSelection(.enabled)
                        .padding(.top, 2)
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Palette.muted)
            }
            .padding(.top, 6)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(group.files.first?.fileName ?? "Duplicate") (\(group.files.count)×)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.text)
                }
                Spacer()
                Text(Formatting.bytes(group.logicalBytes))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .padding(compact ? 8 : 12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.card))
    }
}

// MARK: - 4. Docker View

struct DockerToolView: View {
    @ObservedObject var tools: ToolsCoordinator
    let compact: Bool
    var embedsScrollView: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack {
                if tools.isInspectingDocker {
                    ProgressView().controlSize(.small)
                    Button(L10n.Tools.cancel) { tools.cancelActiveWork() }
                        .buttonStyle(.bordered)
                        .controlSize(compact ? .small : .regular)
                } else {
                    Button(tools.dockerSnapshot == nil ? L10n.Tools.scan : L10n.Tools.rescan) {
                        tools.inspectDocker()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(compact ? .small : .regular)
                }
                if let snap = tools.dockerSnapshot {
                    Pill(
                        text: snap.status.localizedLabel(L10n.activeLanguage),
                        color: snap.status == .ready ? Palette.mint : Palette.coral
                    )
                }
                Spacer()
            }

            if !compact {
                Text(L10n.Tools.dockerSubtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.muted)
            }

            if let snap = tools.dockerSnapshot {
                if snap.status != .ready {
                    Text(L10n.bilingual(es: snap.statusDetailES, en: snap.statusDetailEN))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.coral)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.coral.opacity(0.08)))
                } else {
                    OptionalVerticalScroll(enabled: embedsScrollView) {
                        VStack(alignment: .leading, spacing: 10) {
                            dockerContainersSection(snap.containers)
                            dockerImagesSection(snap.images)
                            dockerBuildCacheSection(snap.buildCacheRecords, summaries: snap.summaries)
                            dockerVolumesSection(snap.volumes)
                        }
                    }
                }
            } else {
                Spacer(minLength: 8)
                Text(L10n.Tools.dockerEmpty)
                    .font(.system(size: compact ? 11 : 12.5))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, compact ? 18 : 36)
                Spacer(minLength: 8)
            }

            if hasAnyDockerSelection {
                Divider()
                HStack {
                    Text(L10n.Tools.selectedCount(selectedDockerResourceCount, "Docker"))
                        .font(.system(size: 11.5, weight: .medium))
                    Spacer()
                    Button(L10n.Tools.reviewPlan) {
                        tools.prepareDockerPlan(fromMenuBar: compact)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(compact ? .small : .regular)
                }
            }
        }
        .padding(compact ? 12 : 24)
    }

    private var hasAnyDockerSelection: Bool {
        !tools.selectedDockerContainerIDs.isEmpty
            || !tools.selectedDockerImageIDs.isEmpty
            || !tools.selectedDockerVolumeNames.isEmpty
            || tools.selectedDockerBuildCacheScope != nil
    }

    private var selectedDockerResourceCount: Int {
        tools.selectedDockerContainerIDs.count
            + tools.selectedDockerImageIDs.count
            + tools.selectedDockerVolumeNames.count
            + (tools.selectedDockerBuildCacheScope == nil ? 0 : 1)
    }

    @ViewBuilder
    private func dockerContainersSection(_ containers: [DockerContainerResource]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(L10n.Tools.dockerSectionContainers) (\(containers.count))")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Palette.muted)
            ForEach(containers) { c in
                let isSelected = tools.selectedDockerContainerIDs.contains(c.id)
                HStack(alignment: .top, spacing: 8) {
                    if c.isRunning {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.mint)
                            .padding(.top, 2)
                    } else {
                        Button { tools.toggleDockerContainer(c) } label: {
                            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                .foregroundStyle(isSelected ? Palette.accent : Palette.muted)
                        }
                        .buttonStyle(.plain)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(c.name) · \(c.state)")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(c.isRunning ? L10n.Tools.dockerRunningProtected : c.imageName)
                            .font(.system(size: 10))
                            .foregroundStyle(c.isRunning ? Palette.mint : Palette.muted)
                    }
                    Spacer()
                    Text(Formatting.bytes(c.writableSizeBytes))
                        .font(.system(size: 11, design: .rounded))
                        .monospacedDigit()
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Palette.card))
            }
        }
    }

    @ViewBuilder
    private func dockerImagesSection(_ images: [DockerImageResource]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(L10n.Tools.dockerSectionImages) (\(images.count))")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Palette.muted)
            ForEach(images) { img in
                let isSelected = tools.selectedDockerImageIDs.contains(img.id)
                HStack(alignment: .top, spacing: 8) {
                    if img.isUsedByRunningContainer {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.amber)
                            .padding(.top, 2)
                    } else {
                        Button { tools.toggleDockerImage(img) } label: {
                            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                .foregroundStyle(isSelected ? Palette.accent : Palette.muted)
                        }
                        .buttonStyle(.plain)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(img.displayName)
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(L10n.Tools.dockerSharedUnique(
                            Formatting.bytes(img.virtualSizeBytes),
                            Formatting.bytes(img.sharedBytes),
                            Formatting.bytes(img.uniqueBytes > 0 ? img.uniqueBytes : img.virtualSizeBytes)
                        ))
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted)
                        if !img.referencingContainerNames.isEmpty {
                            Text(L10n.Tools.dockerUsedBy(img.referencingContainerNames.joined(separator: ", ")))
                                .font(.system(size: 10))
                                .foregroundStyle(img.isUsedByRunningContainer ? Palette.amber : Palette.muted)
                        }
                    }
                    Spacer()
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Palette.card))
            }
        }
    }

    @ViewBuilder
    private func dockerBuildCacheSection(_ records: [DockerBuildCacheRecord], summaries: [DockerCategorySummary]) -> some View {
        let total = summaries.first(where: { $0.typeName.lowercased().contains("build") })?.sizeBytes
            ?? records.reduce(0) { $0 + $1.sizeBytes }
        let reclaimable = summaries.first(where: { $0.typeName.lowercased().contains("build") })?.reclaimableBytes
            ?? records.filter(\.reclaimable).reduce(0) { $0 + $1.sizeBytes }

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(L10n.Tools.dockerSectionBuildCache) (\(records.count))")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                Spacer()
                Text("\(Formatting.bytes(reclaimable)) / \(Formatting.bytes(total))")
                    .font(.system(size: 11, design: .rounded))
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 4) {
                buildCacheScopeOption(scope: nil, title: L10n.Tools.clearSelection)
                buildCacheScopeOption(scope: .reclaimableOnly, title: L10n.Tools.dockerBuildCacheReclaimablePlain)
                buildCacheScopeOption(scope: .all, title: L10n.Tools.dockerBuildCacheAllPlain)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Palette.card))
        }
    }

    @ViewBuilder
    private func buildCacheScopeOption(scope: DockerBuildCachePruneScope?, title: String) -> some View {
        let isSelected = tools.selectedDockerBuildCacheScope == scope
        Button {
            tools.selectedDockerBuildCacheScope = scope
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Palette.accent : Palette.muted)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.text)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func dockerVolumesSection(_ volumes: [DockerVolumeResource]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(L10n.Tools.dockerSectionVolumes) (\(volumes.count))")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Palette.coral)
            ForEach(volumes) { vol in
                let isUnlocked = tools.unlockedDockerVolumeNames.contains(vol.name)
                let isSelected = tools.selectedDockerVolumeNames.contains(vol.name)
                HStack(alignment: .top, spacing: 8) {
                    if vol.isMountedByRunningContainer || !isUnlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(vol.isMountedByRunningContainer ? Palette.coral : Palette.amber)
                            .padding(.top, 2)
                    } else {
                        Button { tools.toggleDockerVolumeSelection(vol) } label: {
                            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                .foregroundStyle(isSelected ? Palette.coral : Palette.muted)
                        }
                        .buttonStyle(.plain)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vol.name)
                            .font(.system(size: 11.5, weight: .semibold))
                        if !vol.mountedByContainerNames.isEmpty {
                            Text(L10n.Tools.dockerUsedBy(vol.mountedByContainerNames.joined(separator: ", ")))
                                .font(.system(size: 10))
                                .foregroundStyle(vol.isMountedByRunningContainer ? Palette.coral : Palette.muted)
                        } else if !isUnlocked {
                            Text(L10n.Tools.dockerVolumeLocked)
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.amber)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Formatting.bytes(vol.sizeBytes))
                            .font(.system(size: 11, design: .rounded))
                            .monospacedDigit()
                        if !vol.isMountedByRunningContainer {
                            Button(isUnlocked ? L10n.Common.actionProtect : L10n.Tools.dockerUnlockVolume) {
                                tools.toggleDockerVolumeLock(vol)
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 10))
                            .foregroundStyle(isUnlocked ? Palette.muted : Palette.coral)
                        }
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Palette.card))
            }
        }
    }
}
