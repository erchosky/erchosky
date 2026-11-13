import SwiftUI
import AppKit
import BrisaCore

private extension NSColor {
    static func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }
}

private extension Color {
    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

enum Palette {
    static let background = Color.adaptive(light: .srgb(245, 245, 247), dark: .srgb(28, 28, 30))
    static let sidebar = Color.adaptive(light: .srgb(236, 236, 239), dark: .srgb(34, 34, 38))
    static let card = Color.adaptive(light: .srgb(255, 255, 255), dark: .srgb(42, 42, 46))
    static let cardHover = Color.adaptive(light: .srgb(238, 240, 244), dark: .srgb(54, 54, 59))
    static let text = Color.adaptive(light: .srgb(29, 29, 31), dark: .srgb(245, 245, 247))
    static let mint = Color.adaptive(light: .srgb(28, 141, 62), dark: .srgb(48, 209, 88))      // Verified eligible ONLY
    static let muted = Color.adaptive(light: .srgb(110, 110, 115), dark: .srgb(152, 152, 157))
    static let amber = Color.adaptive(light: .srgb(198, 102, 0), dark: .srgb(255, 159, 10))
    static let cyan = Color.adaptive(light: .srgb(0, 122, 255), dark: .srgb(10, 132, 255))     // Apple System Blue accent
    static let accent = cyan
    static let coral = Color.adaptive(light: .srgb(217, 45, 32), dark: .srgb(255, 69, 58))
    static let indigo = Color.adaptive(light: .srgb(88, 86, 214), dark: .srgb(94, 92, 230))
    static let categoryIcon = Color.adaptive(light: .srgb(100, 104, 112), dark: .srgb(161, 161, 166))
    static let line = Color.adaptive(light: NSColor.black.withAlphaComponent(0.08), dark: NSColor.white.withAlphaComponent(0.10))
    static let surfaceFill = Color.adaptive(light: NSColor.black.withAlphaComponent(0.045), dark: NSColor.white.withAlphaComponent(0.065))
    static let surfaceStrong = Color.adaptive(light: NSColor.black.withAlphaComponent(0.08), dark: NSColor.white.withAlphaComponent(0.12))
}

struct BrandMark: View {
    var size: CGFloat = 42
    var variant: BrandAssetVariant = .color
    var body: some View {
        Group {
            if let image = BrandAssetCatalog.isotipoImage(variant: variant) {
                Image(nsImage: image)
                    .renderingMode(variant == .monochrome ? .template : .original)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "wind")
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(Palette.cyan)
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

struct LiveBadge: View {
    var body: some View {
        Label(L10n.Common.liveBadge, systemImage: "circle.fill")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(Palette.cyan)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Palette.cyan.opacity(0.08), in: Capsule())
            .accessibilityLabel(L10n.Common.liveHelp)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.035), radius: 3, x: 0, y: 1)
    }
}

struct SectionHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !eyebrow.isEmpty {
            Text(eyebrow.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2.2)
                .foregroundStyle(Palette.cyan)
            }
            Text(title)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .tracking(-0.5)
            if !subtitle.isEmpty {
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyPanel: View {
    let icon: String
    let title: String
    let detail: String
    var useIllustration: Bool = true
    var body: some View {
        VStack(spacing: 12) {
            if useIllustration, let spot = BrandAssetCatalog.illustrationImage(.emptyState, colorScheme: colorScheme) {
                Image(nsImage: spot)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 74, height: 74)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Palette.cyan)
                    .padding(.bottom, 2)
                    .accessibilityHidden(true)
            }
            Text(title).font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }.frame(maxWidth: .infinity).padding(.vertical, 36)
    }
    @Environment(\.colorScheme) private var colorScheme
}

struct Pill: View {
    let text: String
    var icon: String? = nil
    var color: Color = Palette.cyan
    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.11), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.24), lineWidth: 0.8))
    }
}

struct ProgressTrack: View {
    let fraction: Double
    var color: Color = Palette.cyan
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.surfaceFill)
                Capsule().fill(color).frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }.frame(height: 5).accessibilityHidden(true)
    }
}

struct CategoryGlyphBadge: View {
    let category: StorageCategory
    var size: CGFloat = 24

    private var gradientColors: (top: Color, bottom: Color) {
        switch category {
        case .vmContainers:
            return (Color(red: 94/255, green: 106/255, blue: 122/255), Color(red: 67/255, green: 76/255, blue: 89/255))
        case .appCaches:
            return (Color(red: 52/255, green: 145/255, blue: 255/255), Color(red: 10/255, green: 105/255, blue: 218/255))
        case .packageCaches:
            return (Color(red: 49/255, green: 162/255, blue: 196/255), Color(red: 28/255, green: 121/255, blue: 152/255))
        case .developerCaches:
            return (Color(red: 108/255, green: 115/255, blue: 128/255), Color(red: 76/255, green: 82/255, blue: 93/255))
        case .editorExtensions:
            return (Color(red: 107/255, green: 104/255, blue: 224/255), Color(red: 77/255, green: 74/255, blue: 184/255))
        case .toolchainsAndSDKs:
            return (Color(red: 112/255, green: 124/255, blue: 138/255), Color(red: 79/255, green: 89/255, blue: 101/255))
        case .agentAndEditorHistory:
            return (Color(red: 142/255, green: 108/255, blue: 214/255), Color(red: 106/255, green: 76/255, blue: 179/255))
        case .temporaryFiles:
            return (Color(red: 222/255, green: 144/255, blue: 42/255), Color(red: 184/255, green: 110/255, blue: 22/255))
        case .logsAndCrashes:
            return (Color(red: 145/255, green: 126/255, blue: 110/255), Color(red: 112/255, green: 95/255, blue: 82/255))
        case .appLeftovers:
            return (Color(red: 132/255, green: 138/255, blue: 148/255), Color(red: 98/255, green: 104/255, blue: 114/255))
        case .downloadsAndInstallers:
            return (Color(red: 52/255, green: 156/255, blue: 248/255), Color(red: 18/255, green: 115/255, blue: 212/255))
        }
    }

    var body: some View {
        let radius = size * 0.27
        Image(systemName: category.icon)
            .font(.system(size: size * 0.48, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [gradientColors.top, gradientColors.bottom], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.32), Color.black.opacity(0.14)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.75
                    )
            )
            .shadow(color: Color.black.opacity(0.14), radius: 1.5, x: 0, y: 1)
            .accessibilityHidden(true)
    }
}

func categoryName(_ category: BrisaCore.Category) -> String {
    switch category {
    case .cache: return L10n.Common.categorySubCaches
    case .log: return L10n.Common.categorySubLogs
    case .other: return L10n.Common.categorySubOtherMeasured
    }
}

func storageCategoryTitle(_ category: StorageCategory) -> String {
    L10n.bilingual(es: category.titleES, en: category.titleEN)
}

func inventoryItemCount(_ count: Int) -> String {
    L10n.Common.itemCount(count)
}

func storageCategorySummary(_ category: StorageCategory) -> String {
    L10n.bilingual(es: category.aboutES, en: category.aboutEN)
}

/// Visual accent color for a category identity (distinct from status semantics).
func storageCategoryColor(_ category: StorageCategory) -> Color { Palette.categoryIcon }

/// Formats allocated vs logical size without EVER substituting logicalBytes when allocatedBytes == 0.
func honestAllocatedSummary(allocatedBytes: Int64, logicalBytes: Int64) -> String {
    if allocatedBytes == 0 && logicalBytes > 0 {
        return L10n.Common.logicalShort(Formatting.bytes(logicalBytes))
    }
    return Formatting.bytes(allocatedBytes)
}

func categoryStatusLabel(_ report: CategoryReport) -> String {
    switch report.status {
    case .pending: return L10n.Common.statePending
    case .scanning: return L10n.Common.stateScanning
    case .measured:
        return honestAllocatedSummary(allocatedBytes: report.allocatedBytes, logicalBytes: report.logicalBytes)
    case .partial:
        let size = honestAllocatedSummary(allocatedBytes: report.allocatedBytes, logicalBytes: report.logicalBytes)
        return report.itemCount > 0 ? L10n.Common.sizePartial(size) : L10n.Common.statePartial
    case .notInstalled: return L10n.Common.stateNoLocations
    case .noAccess: return L10n.Common.stateNoAccess
    case .empty: return L10n.Common.stateNoItems
    }
}

func categoryStatusBadgeText(_ status: CategoryStatus) -> String {
    switch status {
    case .pending: return L10n.Common.statePending
    case .scanning: return L10n.Common.stateScanning
    case .measured: return L10n.Common.stateMeasured
    case .partial: return L10n.Common.statePartial
    case .notInstalled: return L10n.Common.stateNoLocations
    case .noAccess: return L10n.Common.stateNoAccess
    case .empty: return L10n.Common.stateNoItemsDetected
    }
}

func categoryStatusIcon(_ status: CategoryStatus) -> String {
    switch status {
    case .pending: return "clock"
    case .scanning: return "arrow.triangle.2.circlepath"
    case .measured: return "ruler"
    case .partial: return "exclamationmark.triangle.fill"
    case .notInstalled: return "shippingbox"
    case .noAccess: return "lock.shield.fill"
    case .empty: return "minus.circle"
    }
}

/// Semantic color for category status:
/// - Gray (`Palette.muted`) for `pending`, `notInstalled`, `empty`
/// - Cyan (`Palette.cyan`) for `measured` / `scanning` (informational inventory)
/// - Amber (`Palette.amber`) for `partial`, `noAccess`
/// - Green (`Palette.mint`) is reserved exclusively for verified `eligible` cleanup candidates
func categoryStatusColor(_ status: CategoryStatus) -> Color {
    switch status {
    case .measured, .scanning: return Palette.cyan
    case .partial, .noAccess: return Palette.amber
    case .pending, .notInstalled, .empty: return Palette.muted
    }
}

/// Semantic badge (text, icon, color) for an item's eligibility.
/// Green (`Palette.mint`) is used ONLY for `.eligible`.
func eligibilityBadge(_ file: IndexedFile) -> (text: String, icon: String, color: Color) {
    if file.isPartial {
        return (L10n.Common.eligibilityPartialLocked, "exclamationmark.triangle.fill", Palette.amber)
    }
    switch file.cleanupEligibility {
    case .eligible:
        return (L10n.Common.eligibilityVerifiedEligible, "checkmark.circle.fill", Palette.mint)
    case .inventoryOnly:
        return (L10n.Common.eligibilityInventoryOnly, "eye.fill", Palette.cyan)
    case .lockedNeverSelect:
        return (L10n.Common.eligibilityNeverDelete, "shield.fill", Palette.cyan)
    case .lockedActiveProcess, .lockedOpenFile, .lockedActiveAgent:
        return (L10n.Common.eligibilityInUseLocked, "bolt.horizontal.circle.fill", Palette.amber)
    case .lockedRecent:
        return (L10n.Common.eligibilityRecentKeep, "clock.fill", Palette.muted)
    case .lockedUnverifiedCondition, .lockedRequiresTypedAdapter:
        return (L10n.Common.eligibilityUnverifiedCondition, "lock.fill", Palette.amber)
    case .lockedDirectoryBundle, .lockedProtectedScope:
        return (L10n.Common.eligibilityManualInspection, "folder.badge.gearshape", Palette.cyan)
    }
}

func usageStateLabel(_ state: UsageState) -> String {
    let base: String
    switch state.status {
    case "idle": base = L10n.Common.usageVerifiedIdle
    case "recently_modified": base = L10n.Common.usageRecent
    case "active_process": base = L10n.Common.usageActiveProcess
    case "open_file": base = L10n.Common.usageOpenDescriptor
    case "unknown": base = L10n.Common.usageNotChecked
    default: base = L10n.Common.usageUnknown
    }
    if let detail = state.detail, !detail.isEmpty {
        let localizedDetail: String
        switch detail {
        case "not_checked": localizedDetail = L10n.Common.usageDetailNotChecked
        case "lsof_unavailable": localizedDetail = L10n.Common.usageDetailUnavailable
        case "coding_agent": localizedDetail = L10n.Common.usageDetailActiveAgent
        default: localizedDetail = detail
        }
        return "\(base) (\(localizedDetail))"
    }
    return base
}

func usageStateColor(_ state: UsageState) -> Color {
    switch state.status {
    case "idle": return Palette.cyan
    case "active_process", "open_file", "recently_modified": return Palette.amber
    default: return Palette.muted
    }
}

func dataTierLabel(_ tier: DataTier) -> String {
    switch tier {
    case .regenerable: return L10n.Common.tierRegenerable
    case .costly: return L10n.Common.tierCostly
    case .userData: return L10n.Common.tierUserData
    case .never: return L10n.Common.tierNeverDelete
    }
}

func dateKindLabel(_ kind: String) -> String {
    switch kind {
    case "mtime_directory_latest", "mtime_latest_entry":
        return L10n.Common.dateBasisFolder
    case "mtime_file":
        return L10n.Common.dateBasisFile
    default:
        return L10n.Common.dateBasisDefault
    }
}

func reasonText(_ reason: String) -> String {
    if reason.hasPrefix("Inventory only (OrphanBuildDetector:") {
        return L10n.Common.reasonOrphanDetector
    }
    switch reason {
    case "old_known_extension":
        return L10n.Common.reasonVerifiedIdleFile
    case "list_only_inventory", "inventory_only":
        return L10n.Common.reasonListOnly
    case "never_delete_tier", "never_select":
        return L10n.Common.reasonNeverDelete
    case "typed_adapter_required", "requires_typed_adapter":
        return L10n.Common.reasonExternalCommand
    case "unverified_condition_locked", "unverified_condition":
        return L10n.Common.reasonUnverifiedCondition
    case "active_or_open", "active_process":
        return L10n.Common.reasonInUse
    case "directory_requires_manual_inspection", "directory_bundle_protected":
        return L10n.Common.reasonDirectory
    case "recent_file":
        return L10n.Common.reasonRecent
    case "open_or_uncertain":
        return L10n.Common.reasonOpenOrOutside
    default:
        return L10n.Common.reasonDefaultInventory
    }
}

func relativeScanAge(_ date: Date?) -> String {
    guard let date else { return L10n.Common.stateNotScanned }
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 60 {
        return L10n.Common.timeJustNow
    }
    let minutes = seconds / 60
    if minutes < 60 {
        return L10n.Common.timeMinutesAgo(minutes)
    }
    let hours = minutes / 60
    return L10n.Common.timeHoursAgo(hours)
}

func journalStatusLabel(_ status: String) -> String {
    switch status {
    case "trashed": return L10n.Common.journalTrashed
    case "restored": return L10n.Common.journalRestored
    case "planned": return L10n.Common.journalPlanned
    case "completed": return L10n.Common.journalCompleted
    case "failed": return L10n.Common.journalFailed
    case "partial": return L10n.Common.journalPartial
    case "rejected": return L10n.Common.journalRejected
    case "cancelled": return L10n.Common.journalCancelled
    case "retained": return L10n.Common.journalRetained
    case "intent": return L10n.Common.journalMoveUnconfirmed
    case "restore_intent": return L10n.Common.journalRestoreUnconfirmed
    default: return L10n.Common.journalUnknown
    }
}

func worktreeStatusLabel(_ status: WorktreeAuditStatus) -> String {
    switch status {
    case .cleanIdle: return L10n.Common.worktreeCleanIdle
    case .dirtyUncommitted: return L10n.Common.worktreeDirty
    case .unpushedCommits: return L10n.Common.worktreeUnpushed
    case .locked: return L10n.Common.worktreeLocked
    case .inUseProcess: return L10n.Common.worktreeInUse
    case .recentlyModified: return L10n.Common.worktreeRecent
    case .staleMissingDirectory: return L10n.Common.worktreeMissing
    case .inspectionFailedUnknown: return L10n.Common.worktreeUnknown
    }
}
