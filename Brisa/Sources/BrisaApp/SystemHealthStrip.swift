import SwiftUI
import BrisaCore

struct SystemHealthStrip: View {
    let metrics: MetricsSnapshot?
    private var pressure: String {
        switch metrics?.memoryPressure?.level {
        case .normal: return L10n.Common.stateNormal
        case .warning: return L10n.Common.stateElevated
        case .critical: return L10n.Common.stateCritical
        default: return L10n.Common.stateNoData
        }
    }
    var body: some View {
        Card(padding: 14) {
            HStack(spacing: 14) {
                metric("CPU", metrics?.cpuPercent.map { "\(Int($0.rounded()))%" } ?? "—")
                Divider().frame(height: 22).overlay(Palette.line)
                metric(L10n.Overview.healthRAMUsed, metrics?.memoryUsed.map { Formatting.bytes(Int64(clamping: $0)) } ?? "—")
                Divider().frame(height: 22).overlay(Palette.line)
                metric(L10n.Overview.healthMemoryPressure, pressure,
                       color: metrics?.memoryPressure?.level == .critical ? Palette.coral : metrics?.memoryPressure?.level == .warning ? Palette.amber : Palette.mint)
                Spacer()
            }
        }
    }
    private func metric(_ label: String, _ value: String, color: Color = Palette.text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(Palette.muted)
            Text(value).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(color)
        }
    }
}
