import SwiftUI
import AppKit
import BrisaCore

@main struct BrisaApp: App {
    @StateObject private var state = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Window("Brisa", id: "main") {
            RootView()
                .environmentObject(state)
                .environmentObject(state.tools)
                .environment(\.locale, state.appLocale)
                .frame(minWidth: 1020, minHeight: 700)
                .preferredColorScheme(state.preferredColorScheme)
                .onAppear {
                    delegate.state = state
                    state.applyAppearance()
                }
        }
        .defaultSize(width: 1180, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button(L10n.Activity.menuCommandPalette) { state.showPalette = true; state.revealWindow?() }.keyboardShortcut("k")
                Button(L10n.Activity.menuAnalyzeStorage) { do { try state.startScan() } catch { state.fail(error) } }.keyboardShortcut("r")
            }
        }
        MenuBarExtra {
            MenuPanel()
                .environmentObject(state)
                .environmentObject(state.tools)
                .environment(\.locale, state.appLocale)
                .preferredColorScheme(state.preferredColorScheme)
                .onAppear { state.applyAppearance() }
        } label: {
            MenuBarStatusLabel(
                showFreeSpace: state.showMenuBarFreeSpace,
                language: state.effectiveLanguageCode,
                liveMetrics: state.liveMetrics
            )
        }.menuBarExtraStyle(.window)
    }
}

struct MenuBarStatusLabel: View {
    let showFreeSpace: Bool
    let language: String
    let liveMetrics: LiveMetricsStore

    var body: some View {
        if showFreeSpace {
            ObservedMenuBarStatusLabel(language: language, liveMetrics: liveMetrics)
        } else {
            MenuBarGlyphOnlyLabel()
        }
    }
}

private struct MenuBarGlyphOnlyLabel: View {
    var body: some View {
        HStack(spacing: 0) {
            BrandMenuBarGlyph()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Brisa"))
    }
}

private struct ObservedMenuBarStatusLabel: View {
    let language: String
    @ObservedObject var liveMetrics: LiveMetricsStore

    var body: some View {
        if let freeText = Formatting.menuBarFreeGigabytes(liveMetrics.snapshot?.diskFree) {
            HStack(spacing: 4) {
                BrandMenuBarGlyph()
                Text(freeText)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.MenuBar.statusBarFreeAccessibility(freeText))
        } else {
            MenuBarGlyphOnlyLabel()
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var state: AppState?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let state, state.hasActiveWork {
            state.lastError = L10n.Activity.quitConfirmActiveTask
            return .terminateCancel
        }
        state?.shutdown()
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        state?.shutdown()
    }
}

