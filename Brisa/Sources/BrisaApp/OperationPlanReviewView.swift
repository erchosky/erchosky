import SwiftUI
import BrisaCore

struct OperationPlanReviewView: View {
    @ObservedObject var tools: ToolsCoordinator
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 14) {
            if let report = tools.lastExecutionReport {
                ExecutionResultCard(report: report, compact: compact) {
                    tools.dismissPlanReview()
                }
            } else if let context = tools.pendingPlanContext {
                planContent(context)
            }
        }
        .padding(compact ? 12 : 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(compact ? Color.clear : Palette.background)
    }

    @ViewBuilder
    private func planContent(_ context: PendingPlanContext) -> some View {
        let plan = context.plan
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            // Header
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.Tools.planHeader)
                        .font(.system(size: compact ? 10 : 11, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                    Text(L10n.bilingual(es: plan.titleES, en: plan.titleEN))
                        .font(.system(size: compact ? 13 : 16, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Text(L10n.bilingual(es: plan.scopeDescriptionES, en: plan.scopeDescriptionEN))
                        .font(.system(size: compact ? 10.5 : 12))
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
                if !compact {
                    Button(L10n.Tools.close) {
                        tools.dismissPlanReview()
                    }
                    .buttonStyle(.bordered)
                }
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: compact ? 8 : 10) {
                    // 1. What will change + What is preserved
                    planInfoCard {
                        Text(L10n.Tools.planSummaryWhat)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.text)
                        Text(L10n.Tools.planAffects(plan.affectedResources.count))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.accent)
                        Text("\(L10n.Tools.planPreserved): \(L10n.bilingual(es: plan.preservedSummaryES, en: plan.preservedSummaryEN))")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.mint)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // 2. How much space it takes
                    planInfoCard {
                        HStack {
                            Text(L10n.Tools.planSummarySize)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Palette.text)
                            Spacer()
                            if let total = plan.totalBytes {
                                Text(Formatting.bytes(total))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.text)
                            }
                        }
                        Text(sizeBasisLabel(plan.sizeBasis))
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.muted)
                    }

                    // 3. Recovery / Irreversible warning (always visible before confirm)
                    planInfoCard {
                        Text(L10n.Tools.planSummaryRecovery)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.text)
                        Label {
                            Text(L10n.bilingual(es: plan.restorabilityNoteES, en: plan.restorabilityNoteEN))
                                .font(.system(size: 10.5, weight: plan.restorability.admitsRestore ? .regular : .medium))
                                .foregroundStyle(plan.restorability.admitsRestore ? Palette.mint : Palette.coral)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: plan.restorability.admitsRestore ? "arrow.uturn.backward.circle" : "exclamationmark.triangle.fill")
                                .foregroundStyle(plan.restorability.admitsRestore ? Palette.mint : Palette.coral)
                        }
                    }

                    // Blockers (if any)
                    if !plan.blockers.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(L10n.Tools.planBlockers, systemImage: "lock.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Palette.coral)
                                Spacer()
                                if plan.blockers.contains(where: \.canRecheck) {
                                    if tools.isRecheckingPlan {
                                        ProgressView().controlSize(.mini)
                                    }
                                    Button(L10n.Tools.recheck) {
                                        tools.recheckPendingPlan()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(tools.isRecheckingPlan || tools.isExecutingPlan)
                                }
                            }
                            ForEach(plan.blockers) { blocker in
                                Text("• \(L10n.bilingual(es: blocker.reasonES, en: blocker.reasonEN))")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Palette.coral)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Palette.coral.opacity(0.08))
                        )
                    }

                    // Affected resources list
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.Tools.planAffects(plan.affectedResources.count))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                        ForEach(plan.affectedResources) { res in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: res.isBlocked ? "lock.fill" : (res.mechanism == .trash ? "trash" : "terminal"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(res.isBlocked ? Palette.amber : Palette.muted)
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(L10n.bilingual(es: res.labelES, en: res.labelEN))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Palette.text)
                                        .lineLimit(1)
                                    Text(res.pathOrIdentifier)
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundStyle(Palette.muted)
                                        .lineLimit(compact ? 2 : 3)
                                    if let reasonES = res.blockedReasonES, let reasonEN = res.blockedReasonEN {
                                        Text(L10n.bilingual(es: reasonES, en: reasonEN))
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(Palette.amber)
                                    }
                                }
                                Spacer(minLength: 4)
                                if let bytes = res.sizeBytes {
                                    Text(Formatting.bytes(bytes))
                                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(Palette.text)
                                }
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Palette.surfaceFill)
                    )

                    if plan.requiresExplicitVolumeUnlock {
                        Toggle(isOn: $tools.dockerVolumeConfirmationChecked) {
                            Text(L10n.Tools.planVolumeUnlock)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Palette.coral)
                        }
                        .toggleStyle(.checkbox)
                    }

                    // Collapsible technical & regeneration details
                    planInfoCard {
                        DisclosureGroup(L10n.Tools.planTechnicalSection) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(mechanismText(plan.mechanism))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Palette.muted)
                                if let logical = plan.logicalBytes,
                                   let total = plan.totalBytes,
                                   logical != total {
                                    Text(L10n.Tools.allocatedLogical(Formatting.bytes(total), Formatting.bytes(logical)))
                                        .font(.system(size: 10))
                                        .foregroundStyle(Palette.muted)
                                }
                                if let note = optionalBilingual(plan.sizeNoteES, plan.sizeNoteEN) {
                                    Text(note)
                                        .font(.system(size: 10))
                                        .foregroundStyle(Palette.muted)
                                }
                                Text("\(L10n.Tools.planRegeneration): \(L10n.bilingual(es: plan.regenerationES, en: plan.regenerationEN))")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Palette.text)
                                if !context.technicalCommandsPreview.isEmpty {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(L10n.Tools.planCommandPreview)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Palette.muted)
                                        ForEach(context.technicalCommandsPreview, id: \.self) { cmd in
                                            Text(cmd)
                                                .font(.system(size: 9.5, design: .monospaced))
                                                .foregroundStyle(Palette.muted)
                                                .textSelection(.enabled)
                                        }
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Palette.muted)
                    }
                }
            }
            .frame(maxHeight: compact ? 330 : 420)

            // Footer action buttons
            HStack(spacing: 8) {
                if tools.isExecutingPlan {
                    ProgressView().controlSize(.small)
                    Text(L10n.Tools.working)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                    Spacer()
                    Button(L10n.Tools.cancel) {
                        tools.cancelActiveWork()
                    }
                    .buttonStyle(.bordered)
                } else {
                    if tools.isRecheckingPlan {
                        ProgressView().controlSize(.small)
                        Text(L10n.Tools.working)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.muted)
                    } else if !plan.canExecute {
                        Text(L10n.Tools.planBlockedBanner)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.coral)
                    }
                    Spacer()
                    Button(L10n.Tools.cancel) {
                        tools.dismissPlanReview()
                    }
                    .buttonStyle(.bordered)
                    Button {
                        tools.executePendingPlan()
                    } label: {
                        Text(plan.mechanism == .trash ? L10n.Tools.confirmTrash : L10n.Tools.executePlan)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(plan.restorability.admitsRestore ? Palette.accent : Palette.coral)
                    .disabled(!canSubmit(plan))
                }
            }
        }
    }

    private func canSubmit(_ plan: OperationPlan) -> Bool {
        guard !tools.isRecheckingPlan, plan.canExecute else { return false }
        if plan.requiresExplicitVolumeUnlock && !tools.dockerVolumeConfirmationChecked {
            return false
        }
        return true
    }

    private func sizeBasisLabel(_ basis: SizeMeasurementBasis) -> String {
        switch basis {
        case .measured: return L10n.Tools.planSizeMeasured
        case .estimated: return L10n.Tools.planSizeEstimated
        case .mixed: return L10n.Tools.planSizeMixed
        }
    }

    private func mechanismText(_ mechanism: OperationMechanism) -> String {
        switch mechanism {
        case .trash: return L10n.Tools.planMechanismTrash
        case .toolCommand: return L10n.Tools.planMechanismTool
        case .mixed: return L10n.Tools.planMechanismMixed
        }
    }

    private func optionalBilingual(_ es: String?, _ en: String?) -> String? {
        guard let es, let en else { return nil }
        return L10n.bilingual(es: es, en: en)
    }

    private func planInfoCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Palette.surfaceFill)
        )
    }
}

struct ExecutionResultCard: View {
    let report: OperationExecutionReport
    let compact: Bool
    let onDone: () -> Void

    private var observedFreeDelta: Int64? {
        report.journalEntries.reversed().compactMap(\.freeSpaceDelta).first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(statusColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.system(size: compact ? 13 : 15, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Text(L10n.bilingual(es: report.summaryES, en: report.summaryEN))
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            // 1. Separated outcome counts & recovery
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(report.mechanism == .trash ? L10n.Tools.resultMovedTrashTitle : L10n.Tools.resultCompletedTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Spacer()
                    Text(L10n.Common.itemCount(report.completedItems.count))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.mint)
                }
                HStack(spacing: 8) {
                    Pill(
                        text: report.restorable ? L10n.Tools.planRestorableYes : L10n.Tools.planRestorableNo,
                        color: report.restorable ? Palette.mint : Palette.amber
                    )
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surfaceFill))

            // 2. Observed free-space delta (explicitly distinguished from Trash moves)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L10n.Tools.resultFreeDeltaTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Spacer()
                    Text(observedFreeDelta.map { ($0 >= 0 ? "+" : "") + Formatting.bytes($0) } ?? "—")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.cyan)
                }
                if report.mechanism == .trash {
                    Text(L10n.Tools.resultFreeDeltaTrashNote)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surfaceFill))

            if let output = report.commandOutput, !output.isEmpty {
                DisclosureGroup(L10n.Tools.technicalDetails) {
                    ScrollView {
                        Text(output)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Palette.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 110)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Palette.surfaceFill))
                    .padding(.top, 4)
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Palette.muted)
            }

            HStack {
                Spacer()
                Button(L10n.Tools.close, action: onDone)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(compact ? 4 : 12)
    }

    private var iconName: String {
        switch report.outcome {
        case .completed: return "checkmark.circle.fill"
        case .partial: return "exclamationmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        case .rejected: return "lock.circle.fill"
        case .failed, .planned: return "xmark.octagon.fill"
        }
    }

    private var statusColor: Color {
        switch report.outcome {
        case .completed: return Palette.mint
        case .partial: return Palette.amber
        case .cancelled, .rejected: return Palette.muted
        case .failed, .planned: return Palette.coral
        }
    }

    private var statusTitle: String {
        switch report.outcome {
        case .planned: return L10n.Common.journalPlanned
        case .completed: return L10n.Common.journalCompleted
        case .rejected: return L10n.Common.journalRejected
        case .failed: return L10n.Common.journalFailed
        case .cancelled: return L10n.Common.journalCancelled
        case .partial: return L10n.Common.journalPartial
        }
    }
}
