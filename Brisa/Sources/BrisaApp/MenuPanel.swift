import SwiftUI
import AppKit
import BrisaCore

/// Small immutable presentation snapshot. The panel never owns scan or cleanup policy.
struct MenuPanelSnapshot {
    var computerName: String
    var metrics: MetricsSnapshot?
    var breakdown: HardwareBreakdownSnapshot? = nil
    var categories: [CategoryReport]
    var fileCount: Int
    var allocatedBytes: Int64
    var eligibleBytes: Int64
    var finishedAt: Date?
    var complete: Bool
    var isStale: Bool
    var scanning: Bool
    var operating: Bool
    var toolsBusy: Bool = false
    var selectedCount: Int
    var completedCategories: Int
    var eligibleCount: Int = 0
    var selectedBytes: Int64 = 0
    var lastError: String? = nil
    var appearance: String = "system"
    var language: String = AppLanguage.system.rawValue
    var cpuCoreCount: Int = ProcessInfo.processInfo.activeProcessorCount

    var hasInventory: Bool { finishedAt != nil }
    var hasActiveWork: Bool { scanning || operating || toolsBusy }
}

struct MenuPanelActions {
    var scan: () -> Void = {}
    var cancel: () -> Void = {}
    var category: (StorageCategory) -> Void = { _ in }
    var inventory: () -> Void = {}
    var overview: () -> Void = {}
    var settings: () -> Void = {}
    var review: () -> Void = {}
    var setAppearance: (String) -> Void = { _ in }
    var setLanguage: (String) -> Void = { _ in }
    var quit: () -> Void = {}
    var dismissError: () -> Void = {}
}

struct MenuPanel: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var visibilityToken = UUID()

    var body: some View {
        MenuPanelLiveBridge(
            state: state,
            tools: state.tools,
            visibilityToken: visibilityToken,
            showWindow: showWindow
        )
    }

    private func showWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        dismiss()
    }
}

struct MenuPanelLiveBridge: View {
    @ObservedObject var state: AppState
    @ObservedObject var tools: ToolsCoordinator
    let visibilityToken: UUID
    let showWindow: () -> Void

    var body: some View {
        MenuPanelContent(
            snapshot: MenuPanelSnapshot(
                computerName: state.computerName,
                metrics: nil,
                breakdown: nil,
                categories: state.categories,
                fileCount: state.scan.files.count,
                allocatedBytes: state.measuredBytes,
                eligibleBytes: state.reclaimableAllocatedBytes,
                finishedAt: state.scan.finishedAt,
                complete: state.scan.complete,
                isStale: state.scan.isStale,
                scanning: state.scanning,
                operating: state.operating,
                toolsBusy: tools.hasActiveWork,
                selectedCount: state.selected.count,
                completedCategories: state.scanProgress.completedCategories,
                eligibleCount: state.eligibleFiles.count,
                selectedBytes: state.selectedBytes,
                lastError: state.lastError,
                appearance: state.appearance,
                language: state.language
            ),
            liveMetrics: state.liveMetrics,
            appState: state,
            tools: tools,
            actions: MenuPanelActions(
                scan: { do { try state.startScan() } catch { state.fail(error) } },
                cancel: { state.cancel() },
                category: { category in
                    tools.pushMenuRoute(.category(category))
                },
                inventory: {
                    tools.pushMenuRoute(.exploreSpace)
                },
                overview: { state.page = .overview; showWindow() },
                settings: { state.page = .settings; showWindow() },
                review: {
                    Self.performReviewAction(state: state, tools: tools)
                },
                setAppearance: { state.appearance = $0 },
                setLanguage: { state.language = $0 },
                quit: {
                    if state.hasActiveWork {
                        state.lastError = L10n.Activity.quitConfirmActiveTask
                    } else {
                        NSApp.terminate(nil)
                    }
                },
                dismissError: { state.lastError = nil }
            )
        )
        .background {
            HostingWindowVisibilityObserver(trackResignKey: true) { visible in
                state.liveMetrics.setMenuVisible(visible, token: visibilityToken)
            }
        }
        .onAppear {
            state.liveMetrics.setMenuVisible(true, token: visibilityToken)
        }
        .onDisappear {
            state.liveMetrics.setMenuVisible(false, token: visibilityToken)
        }
    }

    static func performReviewAction(state: AppState, tools: ToolsCoordinator) {
        if !state.selectedFiles.isEmpty {
            tools.prepareInventoryPlan(selectedFiles: state.selectedFiles, fromMenuBar: true)
        } else if !state.eligibleFiles.isEmpty {
            tools.pushMenuRoute(.reviewCandidates)
        } else if let cat = state.categories.first(where: { $0.eligibleCount > 0 })?.category {
            tools.pushMenuRoute(.category(cat))
        }
    }
}

@MainActor
private final class LiveBreakdownHoverController: ObservableObject {
    @Published private(set) var presentedKind: LiveResourceKind?
    @Published private(set) var hoveredCard: LiveResourceKind?
    private var hoveredPopover: LiveResourceKind?
    private var pinnedKind: LiveResourceKind?
    private var openTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?

    func setCardHover(_ kind: LiveResourceKind, isHovering: Bool) {
        if isHovering {
            hoveredCard = kind
            closeTask?.cancel()
            closeTask = nil
            if presentedKind == kind { return }
            openTask?.cancel()
            let delayNs: UInt64 = presentedKind == nil ? 110_000_000 : 35_000_000
            openTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: delayNs)
                guard let self, !Task.isCancelled, self.hoveredCard == kind else { return }
                self.presentedKind = kind
            }
        } else {
            if hoveredCard == kind {
                hoveredCard = nil
            }
            if openTask != nil {
                openTask?.cancel()
                openTask = nil
            }
            scheduleCloseIfNeeded(for: kind)
        }
    }

    func setPopoverHover(_ kind: LiveResourceKind, isHovering: Bool) {
        if isHovering {
            hoveredPopover = kind
            closeTask?.cancel()
            closeTask = nil
        } else {
            if hoveredPopover == kind {
                hoveredPopover = nil
            }
            scheduleCloseIfNeeded(for: kind)
        }
    }

    func togglePin(_ kind: LiveResourceKind) {
        openTask?.cancel()
        closeTask?.cancel()
        if pinnedKind == kind, presentedKind == kind {
            pinnedKind = nil
            presentedKind = nil
        } else {
            pinnedKind = kind
            presentedKind = kind
        }
    }

    func handlePopoverDismissed(_ kind: LiveResourceKind) {
        if pinnedKind == kind { pinnedKind = nil }
        if hoveredPopover == kind { hoveredPopover = nil }
        if presentedKind == kind { presentedKind = nil }
    }

    func reset() {
        openTask?.cancel()
        closeTask?.cancel()
        hoveredCard = nil
        hoveredPopover = nil
        pinnedKind = nil
        presentedKind = nil
    }

    private func scheduleCloseIfNeeded(for kind: LiveResourceKind) {
        guard pinnedKind != kind else { return }
        closeTask?.cancel()
        closeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard let self, !Task.isCancelled else { return }
            guard self.pinnedKind != kind else { return }
            if self.hoveredCard == nil && self.hoveredPopover == nil {
                self.presentedKind = nil
            }
        }
    }
}

/// Shared by the real menu and the native rendering check; no mock readings in production.
struct MenuPanelContent: View {
    let snapshot: MenuPanelSnapshot
    var liveMetrics: LiveMetricsStore? = nil
    var appState: AppState? = nil
    var tools: ToolsCoordinator? = nil
    var actions = MenuPanelActions()
    @StateObject private var hoverController = LiveBreakdownHoverController()
    @State private var showPerformance = false

    private var availableHeight: CGFloat {
        min(640, max(420, floor((NSScreen.main?.visibleFrame.height ?? 860) * 0.68)))
    }

    private var homePanelHeight: CGFloat {
        let base: CGFloat = showPerformance ? 584 : 458
        let extraError: CGFloat = snapshot.lastError == nil ? 0 : 48
        return min(base + extraError, availableHeight)
    }

    private var needsBreakdownPolling: Bool {
        showPerformance && (tools?.menuRoute ?? .home) == .home
    }

    var body: some View {
        Group {
            if let appState, let tools, tools.menuRoute != .home {
                MenuPanelRoutedSubpage(state: appState, tools: tools, footerContent: AnyView(footer))
                    .frame(width: 392, height: min(580, availableHeight))
            } else {
                rootPanelBody
            }
        }
        .background(.regularMaterial)
        .foregroundStyle(Palette.text)
        .tint(Palette.cyan)
        .onAppear {
            liveMetrics?.setMenuBreakdownNeeded(needsBreakdownPolling)
        }
        .onChange(of: showPerformance) { _, _ in
            liveMetrics?.setMenuBreakdownNeeded(needsBreakdownPolling)
        }
        .onChange(of: tools?.menuRoute) { _, _ in
            liveMetrics?.setMenuBreakdownNeeded(needsBreakdownPolling)
        }
        .onDisappear {
            hoverController.reset()
        }
    }

    private var rootPanelBody: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    diskSummarySection
                    primaryTaskCard
                    secondaryEntriesCard
                    performanceDisclosure
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.visible)

            if let error = snapshot.lastError {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Palette.amber)
                    Text(error)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: actions.dismissError) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.Common.actionCloseNotice)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Palette.amber.opacity(0.10))
            }

            Divider()
            footer
        }
        .frame(width: 392, height: homePanelHeight)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.muted)
                .frame(width: 26, height: 26)
                .background(Palette.surfaceFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.computerName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(homeScanStatusSubtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(statusSubtitleColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Group {
                if snapshot.scanning {
                    Button(action: actions.cancel) {
                        Label(L10n.Common.actionCancel, systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: actions.scan) {
                        Label(L10n.Common.actionScan, systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.small)
            .disabled(snapshot.operating)
            .accessibilityIdentifier("menu.scan")
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    private var homeScanStatusSubtitle: String {
        if snapshot.scanning {
            return L10n.MenuBar.statusScanningProgress(snapshot.completedCategories)
        }
        if !snapshot.hasInventory {
            return L10n.MenuBar.statusNotScanned
        }
        if !snapshot.complete {
            return L10n.MenuBar.statusPartialWarning
        }
        if snapshot.isStale {
            return L10n.MenuBar.statusRefreshRecommended
        }
        return L10n.Overview.scannedAgo(relativeScanAge(snapshot.finishedAt))
    }

    private var statusSubtitleColor: Color {
        if snapshot.scanning { return Palette.cyan }
        if snapshot.hasInventory && (!snapshot.complete || snapshot.isStale) { return Palette.amber }
        return Palette.muted
    }

    private var diskSummarySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            telemetrySection(showsPerformance: false, showsDisk: true)
        }
        .background(Palette.surfaceFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var primaryTaskCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if snapshot.scanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.MenuBar.statusScanningProgress(snapshot.completedCategories))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.text)
                    Spacer()
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surfaceFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if snapshot.selectedCount > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Button(action: actions.review) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text(L10n.MenuBar.actionReviewSelection(snapshot.selectedCount, Formatting.bytes(snapshot.selectedBytes)))
                                .font(.system(size: 12.5, weight: .semibold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Palette.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("menu.primary_review")

                    if let appState {
                        HStack {
                            Spacer()
                            Button(L10n.Findings.actionClearSelection) {
                                appState.clearSelection()
                            }
                            .font(.system(size: 10.5))
                            .buttonStyle(.borderless)
                            .foregroundStyle(Palette.muted)
                        }
                    }
                }
            } else if snapshot.eligibleCount > 0 {
                Button(action: actions.review) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13))
                        Text(L10n.MenuBar.actionReviewCandidates(snapshot.eligibleCount, Formatting.bytes(snapshot.eligibleBytes)))
                            .font(.system(size: 12.5, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity)
                    .background(Palette.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("menu.primary_review")
            } else if !snapshot.hasInventory {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.MenuBar.headerScanPrompt)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                    Button(action: actions.scan) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                            Text(L10n.MenuBar.actionScanMac)
                                .font(.system(size: 12.5, weight: .semibold))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Palette.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(snapshot.operating)
                    .accessibilityIdentifier("menu.primary_scan")
                }
                .padding(12)
                .background(Palette.surfaceFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Palette.mint)
                        Text(L10n.MenuBar.emptyAllClearTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.text)
                    }
                    Text(L10n.MenuBar.emptyAllClearSubtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if snapshot.isStale {
                        Button(L10n.MenuBar.actionRescanMac, action: actions.scan)
                            .font(.system(size: 10.5, weight: .medium))
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .padding(.top, 2)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surfaceFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var secondaryEntriesCard: some View {
        VStack(spacing: 6) {
            Button(action: actions.inventory) {
                secondaryEntryRow(
                    icon: "chart.bar.doc.horizontal",
                    color: Palette.cyan,
                    title: L10n.MenuBar.entryExploreSpace,
                    subtitle: L10n.MenuBar.entryExploreSpaceSubtitle,
                    trailing: snapshot.hasInventory ? Formatting.bytes(snapshot.allocatedBytes) : nil
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("menu.entry.explore")

            if let tools {
                Button {
                    tools.pushMenuRoute(.toolsHub)
                } label: {
                    secondaryEntryRow(
                        icon: "wrench.and.screwdriver",
                        color: Palette.indigo,
                        title: L10n.MenuBar.entryTools,
                        subtitle: L10n.MenuBar.entryToolsSubtitle,
                        trailing: nil
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("menu.entry.tools")
            }
        }
    }

    private func secondaryEntryRow(
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        trailing: String?
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12.5))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.muted)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Palette.surfaceFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var performanceDisclosure: some View {
        DisclosureGroup(isExpanded: $showPerformance) {
            telemetrySection(showsPerformance: true, showsDisk: false)
                .padding(.top, 6)
        } label: {
            Label(L10n.MenuBar.sectionPerformance, systemImage: "gauge.with.dots.needle.33percent")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Palette.text)
        }
        .padding(10)
        .background(Palette.surfaceFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func telemetrySection(showsPerformance: Bool, showsDisk: Bool) -> some View {
        if let liveMetrics {
            LiveMenuTelemetryObserver(
                store: liveMetrics,
                snapshot: snapshot,
                hoverController: hoverController,
                showsPerformance: showsPerformance,
                showsDisk: showsDisk
            )
        } else {
            MenuLiveTelemetrySection(
                metrics: snapshot.metrics,
                breakdown: snapshot.breakdown,
                snapshot: snapshot,
                hoverController: hoverController,
                showsPerformance: showsPerformance,
                showsDisk: showsDisk
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: actions.overview) {
                Label(L10n.MenuBar.actionOpenWindowShort, systemImage: "macwindow")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("menu.open_window")

            Spacer(minLength: 4)

            let inPlanOrResult = tools?.menuRoute == .reviewPlan || tools?.menuRoute == .executionResult
            if !inPlanOrResult && snapshot.selectedCount > 0 {
                Button(action: actions.review) {
                    Text(L10n.MenuBar.actionReviewSelection(snapshot.selectedCount, Formatting.bytes(snapshot.selectedBytes)))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Palette.mint)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("menu.footer.review")
            } else if !inPlanOrResult && snapshot.eligibleCount > 0 {
                Button(action: actions.review) {
                    Text(L10n.MenuBar.footerReviewCount(snapshot.eligibleCount))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Palette.mint)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("menu.footer.review")
            }

            Button(action: actions.quit) {
                Image(systemName: "power")
                    .font(.system(size: 11.5))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.muted)
            .help(L10n.MenuBar.footerQuit)
            .accessibilityLabel(L10n.MenuBar.footerQuit)
            .disabled(snapshot.hasActiveWork)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }


}

private struct MenuMetricCard: View {
    let icon: String
    let title: String
    let fraction: Double?
    let detail: String
    let warnAt: Double
    let criticalAt: Double
    var isHighlighted: Bool = false

    private var clamped: Double? {
        fraction.flatMap { $0.isFinite ? min(1, max(0, $0)) : nil }
    }

    private var barColor: Color {
        guard let value = clamped else { return Palette.muted }
        if value >= criticalAt { return Palette.coral }
        if value >= warnAt { return Palette.amber }
        return Palette.cyan
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Palette.muted)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Spacer(minLength: 1)
                Text(clamped.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.surfaceStrong)
                    if let clamped {
                        Capsule()
                            .fill(barColor)
                            .frame(width: max(0, geo.size.width * clamped))
                    }
                }
            }
            .frame(height: 5.5)

            Text(detail)
                .font(.system(size: 9.5))
                .monospacedDigit()
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isHighlighted ? Palette.surfaceStrong.opacity(0.65) : Palette.surfaceFill,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isHighlighted ? Palette.cyan.opacity(0.45) : Palette.line, lineWidth: isHighlighted ? 1.0 : 0.8)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(clamped.map { "\(Int(($0 * 100).rounded()))%, \(detail)" } ?? detail)
    }
}

private struct ResourceBreakdownPopover: View {
    let kind: LiveResourceKind
    let breakdown: HardwareBreakdownSnapshot?
    let metrics: MetricsSnapshot?
    let fallbackCores: Int

    private var title: String {
        switch kind {
        case .memory: return L10n.MenuBar.breakdownMemoryTitle
        case .cpu: return L10n.MenuBar.breakdownCPUTitle
        case .gpu: return L10n.MenuBar.breakdownGPUTitle
        }
    }

    private var subtitle: String {
        switch kind {
        case .memory:
            if let used = metrics?.memoryUsed, let total = metrics?.memoryTotal, total > 0 {
                return L10n.MenuBar.breakdownMemorySubtitle(
                    Formatting.bytes(Int64(clamping: used)),
                    Formatting.bytes(Int64(clamping: total))
                )
            }
            return L10n.Common.stateNoData
        case .cpu:
            let cores = max(1, breakdown?.cpuCoreCount ?? fallbackCores)
            return L10n.MenuBar.breakdownCPUSubtitle(cores)
        case .gpu:
            if let vram = breakdown?.gpuInUseSystemMemoryBytes, vram > 0 {
                return L10n.MenuBar.breakdownGPUSubtitle(Formatting.bytes(Int64(clamping: vram)))
            }
            return L10n.MenuBar.breakdownGPUSubtitlePlain
        }
    }

    private var headerPercentText: String? {
        switch kind {
        case .memory:
            guard let used = metrics?.memoryUsed, let total = metrics?.memoryTotal, total > 0 else { return nil }
            let pct = Int((Double(used) / Double(total) * 100).rounded())
            return L10n.MenuBar.breakdownPercent("\(pct)")
        case .cpu:
            guard let pct = metrics?.cpuPercent, pct.isFinite else { return nil }
            return L10n.MenuBar.breakdownPercent("\(Int(pct.rounded()))")
        case .gpu:
            guard let pct = breakdown?.gpuUtilizationPercent, pct.isFinite else { return nil }
            return L10n.MenuBar.breakdownPercent("\(Int(pct.rounded()))")
        }
    }

    private var consumers: [ResourceConsumerEntry] {
        guard let breakdown else { return [] }
        switch kind {
        case .memory: return breakdown.memoryConsumers
        case .cpu: return breakdown.cpuConsumers
        case .gpu: return breakdown.gpuConsumers
        }
    }

    private var emptyMessage: String {
        switch kind {
        case .memory:
            return L10n.MenuBar.breakdownMemoryEmpty
        case .cpu:
            return L10n.MenuBar.breakdownCPUEmpty
        case .gpu:
            switch breakdown?.gpuStatus {
            case .warmingUp:
                return L10n.MenuBar.breakdownGPUWarmingUp
            case .idle:
                return L10n.MenuBar.breakdownGPUIdle
            case .unavailable, .none:
                return L10n.MenuBar.breakdownGPUUnavailable
            case .available:
                return L10n.MenuBar.breakdownGPUIdle
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                if let headerPercentText {
                    Text(headerPercentText)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.text)
                }
            }

            Divider()

            if consumers.isEmpty {
                HStack(spacing: 8) {
                    if kind == .gpu, breakdown?.gpuStatus == .warmingUp {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: kind == .gpu ? "display.trianglebadge.exclamationmark" : "waveform.path")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)
                    }
                    Text(emptyMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
            } else {
                VStack(spacing: 5) {
                    ForEach(consumers) { entry in
                        ResourceBreakdownRow(kind: kind, entry: entry)
                    }
                }
                Text(methodologyNote)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 282, alignment: .leading)
        .foregroundStyle(Palette.text)
    }

    private var methodologyNote: String {
        switch kind {
        case .memory: return L10n.MenuBar.breakdownMemoryRSSNote
        case .cpu: return L10n.MenuBar.breakdownCPUIntervalNote
        case .gpu: return L10n.MenuBar.breakdownGPUShareNote
        }
    }
}

private struct LiveMenuTelemetryObserver: View {
    @ObservedObject var store: LiveMetricsStore
    let snapshot: MenuPanelSnapshot
    @ObservedObject var hoverController: LiveBreakdownHoverController
    var showsPerformance: Bool = true
    var showsDisk: Bool = true

    var body: some View {
        MenuLiveTelemetrySection(
            metrics: store.snapshot,
            breakdown: store.breakdown,
            snapshot: snapshot,
            hoverController: hoverController,
            showsPerformance: showsPerformance,
            showsDisk: showsDisk
        )
    }
}

private struct MenuLiveTelemetrySection: View {
    let metrics: MetricsSnapshot?
    let breakdown: HardwareBreakdownSnapshot?
    let snapshot: MenuPanelSnapshot
    @ObservedObject var hoverController: LiveBreakdownHoverController
    var showsPerformance: Bool = true
    var showsDisk: Bool = true

    private var activeMetrics: MetricsSnapshot? {
        breakdown?.metrics ?? metrics
    }

    private var memoryFraction: Double? {
        guard let metrics = activeMetrics, let used = metrics.memoryUsed, metrics.memoryTotal > 0 else { return nil }
        return min(1, max(0, Double(used) / Double(metrics.memoryTotal)))
    }

    private var cpuFraction: Double? {
        guard let pct = activeMetrics?.cpuPercent, pct.isFinite else { return nil }
        return min(1, max(0, pct / 100.0))
    }

    private var gpuFraction: Double? {
        guard let pct = breakdown?.gpuUtilizationPercent, pct.isFinite else { return nil }
        return min(1, max(0, pct / 100.0))
    }

    private var diskFraction: Double? {
        guard let usage = MenuDiskUsage(totalBytes: activeMetrics?.diskTotal, freeBytes: activeMetrics?.diskFree,
            scannedBytes: snapshot.allocatedBytes, eligibleBytes: snapshot.eligibleBytes) else { return nil }
        return usage.fraction(usage.used)
    }

    private var pressure: (text: String, color: Color) {
        switch activeMetrics?.memoryPressure?.level {
        case .normal: return (L10n.Common.stateNormal, Palette.cyan)
        case .warning: return (L10n.Common.stateElevated, Palette.amber)
        case .critical: return (L10n.Common.stateCritical, Palette.coral)
        default: return (L10n.Common.stateNoData, Palette.muted)
        }
    }

    private var memoryDetailText: String {
        guard let metrics = activeMetrics, let used = metrics.memoryUsed, metrics.memoryTotal > 0 else {
            return L10n.Common.stateNoData
        }
        return L10n.MenuBar.ramRatio(
            Formatting.bytes(Int64(clamping: used)),
            Formatting.bytes(Int64(clamping: metrics.memoryTotal))
        )
    }

    private var gpuDetailText: String {
        guard let breakdown else {
            return L10n.Common.stateNoData
        }
        if let vram = breakdown.gpuInUseSystemMemoryBytes, vram > 0 {
            return L10n.MenuBar.gpuVRAM(Formatting.bytes(Int64(clamping: vram)))
        }
        if let renderer = breakdown.gpuRendererUtilizationPercent, renderer.isFinite {
            return L10n.MenuBar.gpuRenderer(Int(renderer.rounded()))
        }
        if breakdown.gpuUtilizationPercent != nil {
            return L10n.Common.liveBadge
        }
        return breakdown.gpuStatus == .warmingUp ? L10n.MenuBar.metricSampling : L10n.Common.stateNoData
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsPerformance {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        interactiveMetricCard(
                            kind: .memory,
                            icon: "memorychip",
                            title: L10n.MenuBar.metricMemory,
                            fraction: memoryFraction,
                            detail: memoryDetailText,
                            warnAt: 0.78,
                            criticalAt: 0.90
                        )

                        interactiveMetricCard(
                            kind: .cpu,
                            icon: "cpu",
                            title: L10n.MenuBar.metricCPU,
                            fraction: cpuFraction,
                            detail: activeMetrics?.cpuPercent == nil
                                ? L10n.MenuBar.metricSampling
                                : L10n.MenuBar.cpuCores(breakdown?.cpuCoreCount ?? snapshot.cpuCoreCount),
                            warnAt: 0.75,
                            criticalAt: 0.90
                        )

                        interactiveMetricCard(
                            kind: .gpu,
                            icon: "display",
                            title: L10n.MenuBar.metricGPU,
                            fraction: gpuFraction,
                            detail: gpuDetailText,
                            warnAt: 0.78,
                            criticalAt: 0.92
                        )
                    }

                    HStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Text("Swap")
                                .foregroundStyle(Palette.muted)
                            Text(activeMetrics?.swap?.usedBytes.map { Formatting.bytes(Int64(clamping: $0)) } ?? "—")
                                .foregroundStyle(Palette.text)
                                .fontWeight(.medium)
                        }
                        Spacer()
                        HStack(spacing: 5) {
                            Text(L10n.MenuBar.metricMemoryPressure)
                                .foregroundStyle(Palette.muted)
                            Circle()
                                .fill(pressure.color)
                                .frame(width: 6, height: 6)
                            Text(pressure.text)
                                .foregroundStyle(activeMetrics?.memoryPressure?.level == .normal ? Palette.text : pressure.color)
                                .fontWeight(.medium)
                        }
                    }
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .padding(.horizontal, 2)
                }
                .padding(.top, 4)
            }

            if showsPerformance && showsDisk {
                Divider().padding(.vertical, 8)
            }

            if showsDisk {
                VStack(spacing: 9) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(activeMetrics?.diskFree.map(Formatting.bytes) ?? "—")
                            .font(.system(size: 23, weight: .semibold, design: .rounded))
                            .tracking(-0.5)
                            .monospacedDigit()
                            .foregroundStyle(Palette.text)
                        Text(L10n.MenuBar.diskFree)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)
                        Spacer(minLength: 4)
                        if let total = activeMetrics?.diskTotal, let diskFraction {
                            Text(L10n.MenuBar.diskUsedRatio("\(Int((diskFraction * 100).rounded()))%", Formatting.bytes(total)))
                                .font(.system(size: 10))
                                .monospacedDigit()
                                .foregroundStyle(Palette.muted)
                        }
                    }

                    MenuDiskBar(
                        totalBytes: activeMetrics?.diskTotal,
                        freeBytes: activeMetrics?.diskFree,
                        scannedBytes: snapshot.hasInventory ? snapshot.allocatedBytes : 0,
                        eligibleBytes: snapshot.hasInventory ? snapshot.eligibleBytes : 0
                    )

                    HStack(spacing: 12) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Palette.cyan)
                                .frame(width: 6, height: 6)
                            Text(L10n.MenuBar.diskScanned)
                                .foregroundStyle(Palette.muted)
                            Text(snapshot.hasInventory ? Formatting.bytes(snapshot.allocatedBytes) : "—")
                                .foregroundStyle(Palette.text)
                                .fontWeight(.medium)
                        }
                        Spacer(minLength: 8)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(snapshot.eligibleBytes > 0 ? Palette.mint : Palette.muted.opacity(0.5))
                                .frame(width: 6, height: 6)
                            Text(L10n.MenuBar.diskReviewable)
                                .foregroundStyle(Palette.muted)
                            Text(snapshot.hasInventory ? Formatting.bytes(snapshot.eligibleBytes) : "—")
                                .foregroundStyle(snapshot.eligibleBytes > 0 ? Palette.mint : Palette.muted)
                                .fontWeight(.medium)
                        }
                    }
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    private func interactiveMetricCard(
        kind: LiveResourceKind,
        icon: String,
        title: String,
        fraction: Double?,
        detail: String,
        warnAt: Double,
        criticalAt: Double
    ) -> some View {
        let isHighlighted = hoverController.hoveredCard == kind || hoverController.presentedKind == kind
        return Button {
            hoverController.togglePin(kind)
        } label: {
            MenuMetricCard(
                icon: icon,
                title: title,
                fraction: fraction,
                detail: detail,
                warnAt: warnAt,
                criticalAt: criticalAt,
                isHighlighted: isHighlighted
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoverController.setCardHover(kind, isHovering: isHovering)
        }
        .popover(
            isPresented: popoverBinding(for: kind),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            ResourceBreakdownPopover(
                kind: kind,
                breakdown: breakdown,
                metrics: activeMetrics,
                fallbackCores: snapshot.cpuCoreCount
            )
            .onHover { insidePopover in
                hoverController.setPopoverHover(kind, isHovering: insidePopover)
            }
        }
        .accessibilityIdentifier("menu.metric.\(kind.rawValue)")
    }

    private func popoverBinding(for kind: LiveResourceKind) -> Binding<Bool> {
        Binding(
            get: { hoverController.presentedKind == kind },
            set: { isPresented in
                if !isPresented {
                    hoverController.handlePopoverDismissed(kind)
                }
            }
        )
    }
}

private struct ResourceBreakdownRow: View {
    let kind: LiveResourceKind
    let entry: ResourceConsumerEntry

    private var localizedName: String {
        switch entry.kind {
        case .system:
            return L10n.MenuBar.breakdownSystemLabel
        case .other where entry.id.hasPrefix("other:"):
            return L10n.MenuBar.breakdownOtherLabel
        default:
            return entry.displayName
        }
    }

    private var secondaryValueText: String {
        switch kind {
        case .memory:
            return entry.primaryBytes.map { Formatting.bytes(Int64(clamping: $0)) } ?? "—"
        case .cpu:
            return L10n.MenuBar.breakdownProcessesShort(max(1, entry.processCount))
        case .gpu:
            guard let ns = entry.gpuDeltaNanoseconds else { return "—" }
            return formatGPUNanoseconds(ns)
        }
    }

    private var percentText: String {
        guard let pct = entry.percent, pct.isFinite else { return "—" }
        let formatted: String
        if pct >= 0.95 {
            formatted = "\(Int(pct.rounded()))"
        } else if pct >= 0.05 {
            formatted = String(format: "%.1f", locale: L10n.locale, pct)
        } else {
            formatted = "<0.1"
        }
        return L10n.MenuBar.breakdownPercent(formatted)
    }

    private func formatGPUNanoseconds(_ ns: UInt64) -> String {
        let ms = Double(ns) / 1_000_000.0
        if ms >= 1000.0 {
            let seconds = ms / 1000.0
            return String(format: "%.1f s", locale: L10n.locale, seconds)
        }
        if ms >= 1.0 {
            return "\(Int(ms.rounded())) ms"
        }
        return "<1 ms"
    }

    var body: some View {
        HStack(spacing: 8) {
            AppConsumerIcon(entry: entry)

            Text(localizedName)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(secondaryValueText)
                .font(.system(size: 11.5))
                .monospacedDigit()
                .foregroundStyle(Palette.muted)
                .frame(minWidth: 54, alignment: .trailing)

            Text(percentText)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Palette.text)
                .frame(width: 44, alignment: .trailing)
        }
        .frame(height: 24)
    }
}

private struct AppConsumerIcon: View {
    let entry: ResourceConsumerEntry

    var body: some View {
        Group {
            switch entry.kind {
            case .system:
                ZStack {
                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .fill(Palette.surfaceStrong)
                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.muted)
                }
            case .other:
                if entry.id.hasPrefix("other:") {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            .fill(Palette.surfaceStrong)
                        Image(systemName: "ellipsis")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                    }
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            .fill(Palette.surfaceStrong)
                        Image(systemName: "terminal")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.muted)
                    }
                }
            case .app:
                if let path = entry.bundlePath {
                    Image(nsImage: AppIconCache.shared.icon(forBundlePath: path))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            .fill(Palette.surfaceStrong)
                        Image(systemName: "app.dashed")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                    }
                }
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}

private struct MenuDiskBar: View {
    let totalBytes: Int64?
    let freeBytes: Int64?
    let scannedBytes: Int64
    let eligibleBytes: Int64

    private var segments: MenuDiskUsage? {
        MenuDiskUsage(totalBytes: totalBytes, freeBytes: freeBytes, scannedBytes: scannedBytes, eligibleBytes: eligibleBytes)
    }

    var body: some View {
        GeometryReader { geometry in
            let w = max(0, geometry.size.width)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(Palette.surfaceFill)
                if let seg = segments, seg.used > 0 {
                    let active: [(color: Color, bytes: Int64)] = [
                        (Palette.muted.opacity(0.45), seg.other),
                        (Palette.cyan, seg.scanned),
                        (Palette.mint, seg.eligible)
                    ]
                    HStack(spacing: 0) {
                        ForEach(Array(active.enumerated()), id: \.offset) { _, item in
                            Rectangle()
                                .fill(item.color)
                                .frame(width: w * seg.fraction(item.bytes))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 0.75)
            )
        }
        .frame(height: 9)
        .accessibilityLabel(L10n.MenuBar.diskVolumeUsage)
        .accessibilityValue(
            segments.map { seg in
                let total = totalBytes ?? 0
                let free = freeBytes ?? 0
                let usedPct = "\(Int((seg.fraction(seg.used) * 100).rounded()))%"
                return L10n.MenuBar.diskAccessibilityValue(
                    Formatting.bytes(free),
                    usedPct,
                    Formatting.bytes(total)
                )
            } ?? L10n.Common.stateNoData
        )
        .help(L10n.MenuBar.diskHelp)
    }
}

private struct MenuCategoryRow: View {
    let report: CategoryReport
    let action: () -> Void
    @State private var hovering = false

    private var measured: Bool { report.status == .measured || report.status == .partial && report.itemCount > 0 }
    private var formattedSize: String {
        guard measured else { return "—" }
        return (report.status == .partial ? "≥ " : "") + Formatting.bytes(report.allocatedBytes)
    }
    private var sizeColor: Color { measured ? Palette.text : Palette.muted }

    private var note: String {
        switch report.status {
        case .partial: return L10n.MenuBar.categoryPartialSuffix(inventoryItemCount(report.itemCount))
        case .measured: return inventoryItemCount(report.itemCount)
        case .noAccess: return L10n.MenuBar.categoriesRequiresAuth
        case .pending: return L10n.Common.stateNotScanned
        case .scanning: return L10n.Common.stateScanning
        case .empty: return L10n.Common.stateNoItems
        case .notInstalled: return L10n.MenuBar.categoriesNoLocations
        }
    }

    private var subtitleColor: Color {
        switch report.status {
        case .noAccess: return Palette.amber
        case .scanning: return Palette.cyan
        default: return Palette.muted
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(storageCategoryTitle(report.category))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.text)
                .lineLimit(1)
            HStack(spacing: 4) {
                if report.status == .noAccess {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Palette.amber)
                }
                Text(note)
                    .font(.system(size: 9.5))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sizeLabel: some View {
        Text(formattedSize)
            .font(.system(size: 11.5, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(sizeColor)
            .frame(width: 68, alignment: .trailing)
    }

    private var accessibilitySummary: String {
        var parts = [storageCategoryTitle(report.category), formattedSize, note]
        if report.status == .partial { parts.append(L10n.Common.statePartial) }
        return parts.joined(separator: ", ")
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            CategoryGlyphBadge(category: report.category, size: 24)
            title
            sizeLabel
            Image(systemName: "chevron.right")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(Palette.muted.opacity(0.75))
        }
        .padding(.horizontal, 8)
        .frame(height: 35)
        .contentShape(Rectangle())
        .background(hovering ? Palette.surfaceFill : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    var body: some View {
        Button(action: action) { rowContent }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(L10n.bilingual(es: report.statusNoteES, en: report.statusNoteEN))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("menu.category." + report.category.rawValue)
    }
}

private struct MenuExpandableCategorySection: View {
    @ObservedObject var state: AppState
    @ObservedObject var tools: ToolsCoordinator
    let report: CategoryReport
    let openDetail: () -> Void

    private var isExpanded: Bool {
        tools.expandedMenuCategories.contains(report.category)
    }

    private var measured: Bool {
        report.status == .measured || (report.status == .partial && report.itemCount > 0)
    }

    private var formattedSize: String {
        guard measured else { return "—" }
        return (report.status == .partial ? "≥ " : "") + Formatting.bytes(report.allocatedBytes)
    }

    var body: some View {
        let items = state.files(in: report.category)
        let eligibleCount = items.filter(\.isReviewable).count
        let triState = state.categorySelectionState(report.category)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    tools.toggleExpandedMenuCategory(report.category)
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 16, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                MenuTriStateCheckbox(
                    state: triState,
                    disabled: eligibleCount == 0 || state.scanning || state.operating,
                    action: { state.toggleCategorySelection(report.category) }
                )

                Button(action: openDetail) {
                    HStack(spacing: 8) {
                        CategoryGlyphBadge(category: report.category, size: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(storageCategoryTitle(report.category))
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Palette.text)
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                if report.status == .noAccess {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(Palette.amber)
                                }
                                Text(L10n.MenuBar.categoryItemsCount(report.itemCount, eligible: eligibleCount))
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(report.status == .noAccess ? Palette.amber : Palette.muted)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(formattedSize)
                            .font(.system(size: 11.5, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(measured ? Palette.text : Palette.muted)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(Palette.muted.opacity(0.65))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("menu.category." + report.category.rawValue)
            }
            .padding(.horizontal, 6)
            .frame(height: 35)

            if isExpanded {
                MenuCategoryInlineItems(state: state, category: report.category, maxInlineItems: 18)
            }
        }
    }
}

private struct MenuPanelRoutedSubpage: View {
    @ObservedObject var state: AppState
    @ObservedObject var tools: ToolsCoordinator
    let footerContent: AnyView

    private var routeTitle: String {
        switch tools.menuRoute {
        case .home: return state.computerName
        case .reviewCandidates: return L10n.MenuBar.candidatesTitle
        case .exploreSpace: return L10n.MenuBar.exploreTitle
        case .toolsHub: return L10n.MenuBar.entryTools
        case .category(let cat): return storageCategoryTitle(cat)
        case .toolProjects: return L10n.MenuBar.toolsProjectsShort
        case .toolPackages: return L10n.MenuBar.toolsPackagesShort
        case .toolDuplicates: return L10n.MenuBar.toolsDuplicatesShort
        case .toolApps: return L10n.MenuBar.toolsAppsShort
        case .toolDocker: return L10n.MenuBar.toolsDockerShort
        case .reviewPlan: return L10n.MenuBar.planInlineTitle
        case .executionResult: return L10n.MenuBar.planResultDone
        }
    }

    private var showsExplicitFooter: Bool {
        switch tools.menuRoute {
        case .category, .exploreSpace, .toolsHub:
            return true
        case .home, .reviewCandidates, .toolProjects, .toolPackages, .toolDuplicates, .toolApps, .toolDocker, .reviewPlan, .executionResult:
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar with Back navigation directly inside the popover
            HStack(spacing: 8) {
                Button {
                    if tools.menuRoute == .executionResult || tools.menuRoute == .reviewPlan {
                        tools.dismissPlanReview()
                    } else {
                        tools.popMenuRoute()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text(L10n.MenuBar.navBack)
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Text(routeTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)

                Spacer()

                Button {
                    tools.resetMenuToHome()
                } label: {
                    Image(systemName: "house")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                }
                .buttonStyle(.plain)
                .help(L10n.Common.navOverview)
                .accessibilityLabel(L10n.Common.navOverview)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)

            Divider()

            Group {
                switch tools.menuRoute {
                case .home:
                    EmptyView()
                case .reviewCandidates:
                    MenuReviewCandidatesPanel(state: state, tools: tools)
                case .exploreSpace:
                    MenuExploreSpacePanel(state: state, tools: tools)
                case .toolsHub:
                    MenuToolsHubPanel(tools: tools)
                case .category(let category):
                    MenuCategoryDetailPanel(state: state, category: category)
                case .toolProjects:
                    ProjectArtifactsToolView(tools: tools, compact: true)
                case .toolPackages:
                    PackageManagersToolView(tools: tools, compact: true)
                case .toolDuplicates:
                    ExactDuplicatesToolView(tools: tools, compact: true)
                case .toolApps:
                    AppUninstallerDetailView(tools: tools, applications: state.applications, compact: true)
                        .onAppear { state.loadApplications() }
                case .toolDocker:
                    DockerToolView(tools: tools, compact: true)
                case .reviewPlan, .executionResult:
                    OperationPlanReviewView(tools: tools, compact: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if showsExplicitFooter {
                Divider()
                footerContent
            }
        }
    }
}

