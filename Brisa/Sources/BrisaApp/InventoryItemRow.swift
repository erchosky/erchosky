import SwiftUI
import BrisaCore

/// Display-only wording. Eligibility still comes from the indexed file and AppState.
struct InventoryItemPresentation {
    let file: IndexedFile
    private static let cachedHomeDirectory = NSHomeDirectory()
    private static let cachedHomePrefix = cachedHomeDirectory + "/"

    var selectable: Bool { file.isReviewable }
    var name: String {
        let basename: String
        if let slash = file.path.lastIndex(of: "/") {
            let next = file.path.index(after: slash)
            basename = next < file.path.endIndex ? String(file.path[next...]) : ""
        } else {
            basename = file.path
        }
        let rawTitle = L10n.bilingual(es: file.titleES, en: file.titleEN)
        let title: String = if let sep = rawTitle.range(of: " · ") {
            String(rawTitle[..<sep.lowerBound])
        } else {
            rawTitle
        }
        let opaque = basename.count == 36 && UUID(uuidString: basename) != nil
            || (basename.count >= 20 && basename.allSatisfy(\.isHexDigit))
        if opaque && !title.isEmpty && !title.contains("~/") { return title + " · " + basename.prefix(8) }
        return basename.isEmpty ? file.path : basename
    }
    static func compactPath(_ path: String) -> String {
        path.hasPrefix(cachedHomePrefix) ? "~" + path.dropFirst(cachedHomeDirectory.count) : path
    }
    var location: String {
        if let slash = file.path.lastIndex(of: "/") {
            return Self.compactPath(String(file.path[..<slash]))
        }
        return Self.compactPath(file.path)
    }
    var size: String { (file.isPartial ? "≥ " : "") + (file.allocatedBytes == 0 ? "0 B" : Formatting.bytes(file.allocatedBytes)) }
    var sizeHelp: String {
        if file.isPartial { return L10n.Findings.rowPartialNote }
        if file.allocatedBytes == 0 && file.logicalBytes > 0 {
            return L10n.Findings.rowSparseLogical(Formatting.bytes(file.logicalBytes))
        }
        return L10n.Findings.rowAllocatedHelp
    }
    enum Status {
        case review, inUse, protected, incomplete, recent, unverified, readOnly
        var title: String {
            switch self {
            case .review: return L10n.Findings.rowBadgeReviewable
            case .inUse: return L10n.Findings.rowBadgeInUse
            case .protected: return L10n.Findings.rowBadgeProtected
            case .incomplete: return L10n.Findings.rowBadgePartial
            case .recent: return L10n.Findings.rowBadgeRecent
            case .unverified: return L10n.Findings.rowBadgeUnverified
            case .readOnly: return L10n.Findings.rowBadgeViewOnly
            }
        }
        var color: Color {
            switch self {
            case .review: return Palette.mint
            case .inUse, .incomplete: return Palette.amber
            default: return Palette.muted
            }
        }
    }
    var status: Status {
        if selectable { return .review }
        if file.cleanupEligibility == .lockedNeverSelect || file.cleanupEligibility == .lockedProtectedScope { return .protected }
        if ["active_process", "open_file"].contains(file.usageState.status)
            || [.lockedActiveProcess, .lockedActiveAgent].contains(file.cleanupEligibility) { return .inUse }
        if file.isPartial { return .incomplete }
        if file.cleanupEligibility == .lockedRecent { return .recent }
        if file.cleanupEligibility == .lockedOpenFile { return .unverified }
        return .readOnly
    }
    var explanation: String {
        switch status {
        case .review: return L10n.Findings.rowExplainEligible
        case .inUse:
            if let process = file.usageState.detail, file.usageState.status == "active_process" {
                return L10n.Findings.rowExplainRunningApp(process + ".")
            }
            return L10n.Findings.rowExplainInUse
        case .protected: return L10n.Findings.rowExplainProtected
        case .incomplete: return sizeHelp
        case .recent: return L10n.Findings.rowExplainRecent
        case .unverified: return L10n.Findings.rowExplainUnverified
        case .readOnly:
            return file.isDirectory
                ? L10n.Findings.rowExplainDirectory
                : L10n.Findings.rowExplainViewOnly
        }
    }
}

struct InventoryItemRow: View {
    let file: IndexedFile
    let selected: Bool
    let selectionEnabled: Bool
    let expanded: Bool
    let toggleSelection: () -> Void
    let toggleDetails: () -> Void

    private func accessibleTitle(_ presentation: InventoryItemPresentation) -> String {
        [presentation.name, presentation.location, presentation.size, presentation.status.title].joined(separator: ", ")
    }

    @ViewBuilder private func selectionControl(_ presentation: InventoryItemPresentation) -> some View {
        if presentation.selectable {
            Toggle(isOn: Binding(get: { selected }, set: { _ in toggleSelection() })) { EmptyView() }
                .toggleStyle(.checkbox).labelsHidden().disabled(!selectionEnabled)
                .accessibilityLabel(L10n.Findings.rowSelectAccessibility(file.path))
                .accessibilityIdentifier("file.select." + file.id)
        } else {
            Color.clear.frame(width: 18, height: 18).accessibilityHidden(true)
        }
    }

    private func rowLabel(_ presentation: InventoryItemPresentation) -> some View {
        HStack(spacing: 12) {
            Image(systemName: file.isDirectory ? "folder" : "doc")
                .font(.system(size: 15)).foregroundStyle(Palette.categoryIcon).frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.name).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.text).lineLimit(1)
                Text(presentation.location).font(.system(size: 10)).foregroundStyle(Palette.muted)
                    .lineLimit(1).truncationMode(.middle)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(presentation.size).font(.system(size: 12, weight: .medium)).monospacedDigit()
                .foregroundStyle(Palette.text).frame(width: 88, alignment: .trailing).help(presentation.sizeHelp)
            Text(presentation.status.title).font(.system(size: 10)).foregroundStyle(presentation.status.color)
                .lineLimit(1).frame(width: 110, alignment: .trailing).help(presentation.explanation)
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 8, weight: .semibold)).foregroundStyle(Palette.muted).frame(width: 10)
        }.frame(minHeight: 46).contentShape(Rectangle())
    }

    var body: some View {
        let presentation = InventoryItemPresentation(file: file)
        HStack(spacing: 10) {
            selectionControl(presentation).frame(width: 18)
            Button(action: toggleDetails) { rowLabel(presentation) }
                .buttonStyle(.plain).accessibilityLabel(accessibleTitle(presentation))
                .accessibilityValue(expanded ? L10n.Findings.rowDetailsOpen : L10n.Findings.rowDetailsClosed)
                .accessibilityHint(L10n.Findings.rowDetailsHelp)
                .accessibilityIdentifier("file.inspect." + file.id)
        }.padding(.horizontal, 14).padding(.vertical, 5)
            .background(expanded || selected ? Palette.cyan.opacity(0.035) : Color.clear)
    }
}

struct InventoryItemDetails: View {
    let file: IndexedFile
    let actionsEnabled: Bool
    let reveal: () -> Void
    let focusMap: () -> Void
    let protect: () -> Void
    @State private var showTechnical = false

    private func regenTint(_ behavior: RegenerationBehavior) -> Color {
        switch behavior {
        case .rebuilds: return Palette.cyan
        case .downloads: return Palette.amber
        case .gone: return Palette.coral
        case .unknown: return Palette.muted
        }
    }

    private func guidanceLine(label: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.muted)
                .frame(width: 92, alignment: .leading)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Palette.text.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func regenDetailsValue(_ behavior: RegenerationBehavior, raw: String?) -> String {
        let base = L10n.Findings.regenBehaviorLabel(behavior)
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return base
        }
        return "\(base) (\(raw))"
    }

    var body: some View {
        let presentation = InventoryItemPresentation(file: file)
        let guidance = RegenerationGuidance.describe(for: file)
        VStack(alignment: .leading, spacing: 12) {
            Text(presentation.explanation).font(.system(size: 12)).foregroundStyle(Palette.text.opacity(0.9))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(L10n.bilingual(es: guidance.familyTitleES, en: guidance.familyTitleEN))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.text.opacity(0.92))
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                    Text(L10n.Findings.regenBehaviorLabel(guidance.behavior))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(regenTint(guidance.behavior))
                }
                guidanceLine(
                    label: L10n.Findings.rowGuidanceWhat,
                    text: L10n.bilingual(es: guidance.whatItIsES, en: guidance.whatItIsEN)
                )
                guidanceLine(
                    label: L10n.Findings.rowGuidanceLost,
                    text: L10n.bilingual(es: guidance.whatIsLostES, en: guidance.whatIsLostEN)
                )
                guidanceLine(
                    label: L10n.Findings.rowGuidanceRegen,
                    text: L10n.bilingual(es: guidance.regenerationES, en: guidance.regenerationEN)
                )
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surfaceFill, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.line, lineWidth: 1))
            Text(file.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled)
            HStack(spacing: 18) {
                Text(L10n.Findings.rowLastChange(file.modifiedAt.formatted(date: .abbreviated, time: .omitted)))
                if file.isDirectory { Text("· " + L10n.Findings.rowFilesCounted(file.childCount)) }
            }.font(.system(size: 10)).foregroundStyle(Palette.muted)
            HStack(spacing: 12) {
                Button(L10n.Common.actionShowInFinder, action: reveal)
                if file.isDirectory { Button(L10n.Findings.rowViewOnMap, action: focusMap) }
                Button(L10n.Common.actionProtect, action: protect).disabled(!actionsEnabled)
            }.controlSize(.small)
            DisclosureGroup(L10n.Findings.rowTechnicalDetails, isExpanded: $showTechnical) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(L10n.Findings.rowAllocatedSize(Formatting.bytes(file.allocatedBytes)))
                    Text(L10n.Findings.rowLogicalSize(Formatting.bytes(file.logicalBytes)))
                    Text(L10n.Findings.rowSelectableSize(Formatting.bytes(file.reclaimableBytes)))
                    Text(L10n.Findings.rowDateBasis(dateKindLabel(file.dateKind)))
                    if let capacity = file.virtualCapacityBytes { Text(L10n.Findings.rowVirtualCapacity(Formatting.bytes(capacity))) }
                    if file.isPartial, let reason = file.partialReason { Text(MeasurementNotes.describe(reason, language: L10n.code)).foregroundStyle(Palette.amber) }
                    Text(L10n.bilingual(es: file.explanationES, en: file.explanationEN))
                    Text(reasonText(file.reason))
                    Text("ID: \(file.id) · inode: \(file.identity.device):\(file.identity.inode)")
                    Text(L10n.Findings.rowRule((file.ruleID ?? "—") + " · " + (file.sourceGroup ?? "—")))
                    Text(L10n.Findings.rowRegenBehavior(regenDetailsValue(guidance.behavior, raw: file.regenBehavior)))
                    Text(L10n.Findings.rowDataType(dataTierLabel(file.dataKind)))
                    Text(L10n.Findings.rowUsageInspection(usageStateLabel(file.usageState)))
                    Text(L10n.Findings.rowConfidence(file.confidence))
                    if let source = file.provenance { Text(source) }
                    if let source = file.upstreamProvenance { Text("\(source.repository) @ \(source.commit) · \(source.upstreamID) · \(source.license)\n\(source.localReviewNote)") }
                    if !file.conditionsSummary.isEmpty { Text(file.conditionsSummary.joined(separator: ", ")) }
                }.font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.top, 8).textSelection(.enabled)
            }.font(.system(size: 10)).foregroundStyle(Palette.muted)
        }.padding(.leading, 60).padding(.trailing, 18).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading).background(Palette.cyan.opacity(0.025))
    }
}
