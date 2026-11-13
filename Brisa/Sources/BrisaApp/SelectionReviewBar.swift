import SwiftUI
import BrisaCore

struct SelectionReviewBar: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        if !state.selected.isEmpty {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.Findings.selectionAllocatedSummary(count: state.selected.count, size: Formatting.bytes(state.selectedBytes)))
                        .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    Text(L10n.Findings.selectionHint)
                        .font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer()
                if state.operating {
                    Button(L10n.Findings.selectionCancelRemaining) { state.cancel() }.buttonStyle(.bordered)
                }
                Button {
                    Task { do { _ = try await state.cleanSelection() } catch { state.fail(error) } }
                } label: {
                    Label(L10n.Findings.selectionReviewButton, systemImage: "trash").padding(5)
                }
                .buttonStyle(.borderedProminent).tint(Palette.mint).disabled(state.operating || state.scanning)
            }
            .padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line, lineWidth: 1))
            .padding(.horizontal, 28).padding(.bottom, 16)
        }
    }
}
