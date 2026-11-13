import SwiftUI
import BrisaCore

func categoryPlainSummary(_ category: StorageCategory) -> String {
    L10n.Findings.categorySummary(for: category)
}

struct CategoryExplanationView: View {
    let report: CategoryReport
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(storageCategoryTitle(report.category)).font(.system(size: 14, weight: .semibold))
            Text(categoryPlainSummary(report.category)).font(.callout).foregroundStyle(Palette.muted)
            if report.status == .partial {
                Text(L10n.Findings.categoryPartialNote)
                    .font(.caption).foregroundStyle(Palette.amber)
            }
            Divider()
            Text(L10n.Findings.categoryScanDetails).font(.caption.weight(.semibold))
            Text(L10n.bilingual(es: report.statusNoteES, en: report.statusNoteEN))
                .font(.caption).foregroundStyle(Palette.muted)
            if report.logicalBytes > 0 { Text(L10n.Findings.categoryLogicalSize(Formatting.bytes(report.logicalBytes))).font(.caption).foregroundStyle(Palette.muted) }
            else if report.allocatedBytes == 0 && report.itemCount > 0 {
                Text(L10n.Findings.categorySizeNotMeasured).font(.caption).foregroundStyle(Palette.muted)
            }
            if let capacity = report.virtualCapacityBytes { Text(L10n.Findings.categoryVirtualCapacity(Formatting.bytes(capacity))).font(.caption).foregroundStyle(Palette.muted) }
        }
        .padding(16).frame(width: 310, alignment: .leading)
    }
}
