import SwiftUI
import BrisaCore

struct OverviewView: View {
    @EnvironmentObject var state: AppState
    @State private var showAnalysisDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                SectionHeading(eyebrow: "", title: L10n.Overview.title, subtitle: "")
                scanButton
            }
            HStack(alignment: .top, spacing: 14) {
                LiveMetricsRegion(store: state.liveMetrics) { _ in
                    freeSpaceCompactCard
                }
                reviewableCandidatesCompactCard
            }
            if state.scanning {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(L10n.Overview.scanningTitle)
                    Spacer()
                    Text("\(state.scanProgress.completedCategories)/\(state.scanProgress.totalCategories)")
                }.font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            if state.scan.finishedAt != nil {
                HStack(spacing: 8) {
                    if !state.scan.complete { Image(systemName: "info.circle").foregroundStyle(Palette.amber) }
                    Text(state.scan.isStale ? L10n.Overview.refreshNeeded
                         : state.scan.complete ? L10n.Overview.scannedAgo(relativeScanAge(state.scan.finishedAt))
                         : L10n.Overview.partialBannerTitle)
                    Spacer()
                    Button(L10n.Overview.details) { showAnalysisDetails.toggle() }.buttonStyle(.plain).foregroundStyle(Palette.cyan)
                }.font(.system(size: 10)).foregroundStyle(Palette.muted)
                .popover(isPresented: $showAnalysisDetails) { analysisDetails }
            }
            tasksSection
            if state.scan.finishedAt != nil || state.scanning {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.Overview.sectionSpaceByCategory).font(.system(size: 14, weight: .semibold))
                    Card(padding: 16) {
                        VStack(spacing: 7) {
                            ForEach(state.categories) { report in
                                Button { state.openCategory(report.category) } label: { categoryRow(report) }
                                    .buttonStyle(.plain).accessibilityIdentifier("category." + report.category.rawValue)
                                if report.id != state.categories.last?.id { Divider().overlay(Palette.line.opacity(0.65)) }
                            }
                        }
                    }
                }
            }
            DisclosureGroup(L10n.Overview.sectionMacPerformance) {
                LiveMetricsRegion(store: state.liveMetrics) { reading in
                    VStack(alignment: .leading, spacing: 12) {
                        SystemHealthStrip(metrics: reading)
                        DisclosureGroup(L10n.Overview.sectionMoreSystemInfo) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                                cpuTile; ramTile; swapTile; memoryPressureTile; localSnapshotsTile
                            }.padding(.top, 10)
                        }.font(.system(size: 11))
                    }.padding(.top, 10)
                }
            }.font(.system(size: 12)).foregroundStyle(Palette.muted)
        }
    }

    private var analysisDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Overview.partialPopoverTitle).font(.headline)
            Text(L10n.Overview.partialPopoverCounts(Formatting.bytes(state.measuredBytes), state.scan.files.count))
                .font(.callout)
            if !state.scan.complete {
                Text(L10n.Overview.partialPopoverBody)
                    .font(.caption).foregroundStyle(Palette.muted)
                ForEach(state.categories.filter { $0.status == .partial || $0.status == .noAccess }) { report in
                    HStack {
                        Text(storageCategoryTitle(report.category))
                        Spacer()
                        Text(report.status == .noAccess ? L10n.Overview.accessNone : L10n.Overview.accessPartial)
                            .foregroundStyle(Palette.muted)
                    }.font(.system(size: 10))
                }
            }
            Text(relativeScanAge(state.scan.finishedAt)).font(.caption).foregroundStyle(Palette.muted)
        }.padding(20).frame(width: 370)
    }

    var scanButton: some View {
        Group {
            if state.scanning {
                Button { state.cancel() } label: {
                    Label(L10n.Overview.cancelScan, systemImage: "stop.circle").padding(4)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("overview.cancelScan")
            } else {
                Button {
                    do { try state.startScan() } catch { state.fail(error) }
                } label: {
                    Label(L10n.Common.actionScan, systemImage: "arrow.triangle.2.circlepath").padding(4)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.cyan)
                .disabled(state.operating)
                .accessibilityIdentifier("overview.scan")
            }
        }
    }

    // MARK: - Compact Header Cards

    private var freeSpaceCompactCard: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 9) {
                Text(L10n.Overview.cardFreeSpace).font(.system(size: 12)).foregroundStyle(Palette.muted)
                Text(state.metrics?.diskFree.map(Formatting.bytes) ?? "—")
                    .font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.75)
                ProgressTrack(fraction: usedFraction, color: Palette.cyan)
                HStack {
                    Text(L10n.Overview.cardOfCapacity(state.metrics?.diskTotal.map(Formatting.bytes) ?? "—"))
                    Spacer()
                    Text(state.metrics?.diskTotal == nil ? "—" : String(format: "%.0f%% %@", usedFraction * 100, L10n.Overview.cardUsedLabel))
                }.font(.system(size: 10)).foregroundStyle(Palette.muted)
            }.frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        }
    }

    private var reviewableCandidatesCompactCard: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 9) {
                Text(L10n.Overview.cardReviewable).font(.system(size: 12)).foregroundStyle(Palette.muted)
                Text(state.scan.finishedAt == nil ? (state.scanning ? L10n.Common.stateScanning : "—") : Formatting.bytes(state.reclaimableAllocatedBytes))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(state.eligibleFiles.isEmpty ? Palette.muted : Palette.mint)
                    .lineLimit(1).minimumScaleFactor(0.75)
                Text(state.scan.finishedAt == nil
                     ? L10n.Overview.cardScanToFind
                     : L10n.Overview.selectableFiles(state.eligibleFiles.count))
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                Button {
                    if state.eligibleFiles.isEmpty {
                        state.openExploreSpace()
                    } else {
                        state.openCleanCandidates()
                    }
                } label: {
                    Label(state.eligibleFiles.isEmpty ? L10n.Overview.actionBrowseFiles : L10n.Overview.actionReviewFiles, systemImage: "arrow.right")
                        .font(.system(size: 11, weight: .medium))
                }.buttonStyle(.plain).foregroundStyle(Palette.cyan)
                    .disabled(state.scan.finishedAt == nil)
                    .accessibilityIdentifier("overview.review")
            }.frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        }
    }

    // MARK: - Category Row

    func categoryRow(_ report: CategoryReport) -> some View {
        let measured = report.status == .measured || report.status == .partial && report.itemCount > 0
        return HStack(spacing: 12) {
            CategoryGlyphBadge(category: report.category, size: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(storageCategoryTitle(report.category)).font(.system(size: 12, weight: .medium)).lineLimit(1)
                HStack(spacing: 5) {
                    if report.status == .partial || report.status == .noAccess {
                        Circle().fill(Palette.amber).frame(width: 4, height: 4)
                    }
                    Text(measured ? inventoryItemCount(report.itemCount) : categoryStatusBadgeText(report.status))
                    if report.category.isPrimarilyInventoryOnly { Text("· " + L10n.Overview.rowViewOnly) }
                    if report.eligibleCount > 0 {
                        Text("· " + L10n.Overview.rowReviewableSuffix("\(report.eligibleCount)")).foregroundStyle(Palette.mint)
                    }
                }.font(.system(size: 9)).foregroundStyle(Palette.muted).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(measured ? (report.status == .partial ? "≥ " : "") + Formatting.bytes(report.allocatedBytes) : "—")
                .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                .foregroundStyle(measured ? Palette.text : Palette.muted)
                .frame(width: 86, alignment: .trailing)
            Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(Palette.muted)
        }
        .padding(.vertical, 5)
        .help(L10n.bilingual(es: report.statusNoteES, en: report.statusNoteEN))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(storageCategoryTitle(report.category) + ", " + categoryStatusLabel(report) + ", " + inventoryItemCount(report.itemCount))
        .accessibilityAddTraits(.isButton)
    }

    var usedFraction: Double {
        guard let total = state.metrics?.diskTotal, let free = state.metrics?.diskFree, total > 0 else { return 0 }
        return min(1, max(0, Double(total - free) / Double(total)))
    }

    // MARK: - Task Hub

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Overview.tasksHeading)
                .font(.system(size: 14, weight: .semibold))

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 220), spacing: 12),
                    GridItem(.flexible(minimum: 220), spacing: 12)
                ],
                spacing: 12
            ) {
                taskActionCard(
                    icon: "sparkles",
                    color: Palette.mint,
                    title: L10n.Overview.tasksCleanTitle,
                    description: L10n.Overview.tasksCleanDesc,
                    badge: state.eligibleFiles.isEmpty ? nil : L10n.Overview.tasksCleanStatusCount(state.eligibleFiles.count, Formatting.bytes(state.reclaimableAllocatedBytes)),
                    identifier: "overview.task.clean"
                ) {
                    state.openCleanCandidates()
                }

                taskActionCard(
                    icon: "externaldrive",
                    color: Palette.cyan,
                    title: L10n.Overview.tasksExploreTitle,
                    description: L10n.Overview.tasksExploreDesc,
                    identifier: "overview.task.explore"
                ) {
                    state.openExploreSpace()
                }

                taskActionCard(
                    icon: "square.on.square",
                    color: Palette.cyan,
                    title: L10n.Overview.tasksDuplicatesTitle,
                    description: L10n.Overview.tasksDuplicatesDesc,
                    identifier: "overview.task.duplicates"
                ) {
                    state.openDuplicates()
                }

                taskActionCard(
                    icon: "square.grid.2x2",
                    color: Palette.cyan,
                    title: L10n.Overview.tasksAppsTitle,
                    description: L10n.Overview.tasksAppsDesc,
                    identifier: "overview.task.apps"
                ) {
                    state.openApplications()
                }

                taskActionCard(
                    icon: "clock.arrow.circlepath",
                    color: Palette.muted,
                    title: L10n.Overview.tasksHistoryTitle,
                    description: L10n.Overview.tasksHistoryDesc,
                    identifier: "overview.task.history"
                ) {
                    state.openHistory()
                }

                taskActionCard(
                    icon: "wrench.and.screwdriver",
                    color: Palette.muted,
                    title: L10n.Overview.tasksAdvancedTitle,
                    description: L10n.Overview.tasksAdvancedDesc,
                    identifier: "overview.task.advanced"
                ) {
                    state.openAdvancedTools(.projects)
                }
            }
        }
    }

    private func taskActionCard(
        icon: String,
        color: Color,
        title: String,
        description: String,
        badge: String? = nil,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Card(padding: 15) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(color)
                            .frame(width: 22, height: 22)
                            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.text)
                        Spacer(minLength: 4)
                        if let badge {
                            Pill(text: badge, color: color)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                    }
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - System Metric & Diagnostic Tiles

    private var cpuTile: some View {
        let pct = state.metrics?.cpuPercent
        let valueStr = pct.map { String(format: "%.1f%%", $0) } ?? L10n.MenuBar.metricSampling
        return diagnosticTile(
            icon: "cpu",
            label: "CPU",
            value: valueStr,
            badgeText: pct != nil ? L10n.Common.stateMeasured : L10n.Common.statePending,
            badgeColor: pct != nil ? Palette.cyan : Palette.muted,
            fraction: (pct ?? 0) / 100.0,
            detail: L10n.Overview.tileCPUDetailSource
        )
    }

    private var ramTile: some View {
        let used = state.metrics?.memoryUsed
        let total = max(state.metrics?.memoryTotal ?? 1, 1)
        let pct = used.map { Double($0) / Double(total) * 100.0 }
        let valueStr: String = {
            guard let u = used, let p = pct else { return "—" }
            return "\(Formatting.bytes(Int64(u))) (\(String(format: "%.0f%%", p)))"
        }()
        return diagnosticTile(
            icon: "memorychip",
            label: L10n.Overview.tileRAMUsedCaps,
            value: valueStr,
            badgeText: Formatting.bytes(Int64(total)),
            badgeColor: Palette.cyan,
            fraction: Double(used ?? 0) / Double(total),
            detail: L10n.Overview.tileRAMCaption
        )
    }

    private var swapTile: some View {
        let swap = state.metrics?.swap
        let used = swap?.usedBytes
        let total = swap?.totalBytes ?? 0
        let valueStr: String = {
            guard swap?.status == .available, let u = used else { return L10n.Common.stateUnknown }
            return "\(Formatting.bytes(Int64(u))) / \(Formatting.bytes(Int64(total)))"
        }()
        let frac = total > 0 && used != nil ? Double(used!) / Double(total) : 0
        return diagnosticTile(
            icon: "arrow.left.arrow.right.square",
            label: "SWAP (VM)",
            value: valueStr,
            badgeText: swap?.status == .available ? "vm.swapusage" : L10n.Common.stateNoData,
            badgeColor: swap?.status == .available ? Palette.cyan : Palette.muted,
            fraction: frac,
            detail: L10n.Overview.tileSwapCaption
        )
    }

    private var memoryPressureTile: some View {
        let pressure = state.metrics?.memoryPressure
        let level = pressure?.level ?? .unknown
        let (labelStr, color): (String, Color) = {
            switch level {
            case .normal: return (L10n.Common.stateNormal, Palette.cyan)
            case .warning: return (L10n.Common.stateWarning, Palette.amber)
            case .critical: return (L10n.Common.stateCritical, Palette.coral)
            case .unknown: return (L10n.Common.stateUnknownFem, Palette.muted)
            }
        }()
        let comp = pressure?.compressedBytes.map { Formatting.bytes(Int64($0)) } ?? "—"
        return diagnosticTile(
            icon: "gauge.with.dots.needle.33percent",
            label: L10n.Overview.tilePressureCaps,
            value: labelStr,
            badgeText: L10n.Overview.tilePressureComp(comp),
            badgeColor: color,
            fraction: level == .critical ? 0.95 : (level == .warning ? 0.6 : (level == .normal ? 0.2 : 0)),
            detail: L10n.Overview.tilePressureCaption
        )
    }

    private var localSnapshotsTile: some View {
        let snaps = state.metrics?.localSnapshots
        let valueStr: String = {
            guard snaps?.status == .available, let count = snaps?.totalCount else {
                return L10n.Common.stateUnavailable
            }
            return L10n.Overview.tileSnapshotsCount(count)
        }()
        let subBadge: String = {
            guard snaps?.status == .available else { return "tmutil" }
            return "TM: \(snaps?.timeMachineCount ?? 0) · OS: \(snaps?.osUpdateCount ?? 0)"
        }()
        return diagnosticTile(
            icon: "clock.badge.checkmark",
            label: L10n.Overview.tileSnapshotsCaps,
            value: valueStr,
            badgeText: subBadge,
            badgeColor: snaps?.status == .available ? Palette.cyan : Palette.muted,
            fraction: 0,
            detail: L10n.Overview.tileSnapshotsCaption
        )
    }

    private var gpuTile: some View {
        diagnosticTile(
            icon: "square.3.layers.3d",
            label: "GPU",
            value: L10n.Common.stateNoData,
            badgeText: L10n.Common.stateUnavailable,
            badgeColor: Palette.muted,
            fraction: 0,
            detail: L10n.Overview.tileGPUCaption
        )
    }

    private func diagnosticTile(
        icon: String,
        label: String,
        value: String,
        badgeText: String,
        badgeColor: Color,
        fraction: Double,
        detail: String
    ) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label(label, systemImage: icon)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                    Spacer()
                    Pill(text: badgeText, color: badgeColor)
                }
                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                ProgressTrack(fraction: fraction, color: badgeColor)
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
