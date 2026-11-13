import SwiftUI
import BrisaCore

struct RootView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) var openWindow
    @State private var windowVisibilityToken = UUID()
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Palette.line).frame(width: 1)
            VStack(spacing: 0) {
                topbar
                if !state.welcomed { WelcomeView() }
                else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 0) {
                                Color.clear.frame(height: 1).id("scroll.top")
                                Group {
                                    switch state.page {
                                    case .overview: OverviewView()
                                    case .findings: FindingsView()
                                    case .applications: ApplicationsView()
                                    case .activity: ActivityView()
                                    case .settings: SettingsView()
                                    }
                                }.padding(30).frame(maxWidth: 1250).frame(maxWidth: .infinity)
                            }
                        }
                        .onChange(of: state.category) { _, _ in
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo("scroll.top", anchor: .top)
                            }
                        }
                        .onChange(of: state.cleanMode) { _, _ in
                            proxy.scrollTo("scroll.top", anchor: .top)
                        }
                        .onChange(of: state.page) { _, _ in
                            proxy.scrollTo("scroll.top", anchor: .top)
                        }
                    }
                }
                if state.page == .findings,
                   state.cleanMode == .candidates || state.cleanMode == .explore,
                   !state.selected.isEmpty || state.operating {
                    SelectionReviewBar().padding(.horizontal, 20).padding(.vertical, 10)
                        .background(Palette.sidebar)
                }
                if let error = state.lastError {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.shield").foregroundStyle(Palette.amber)
                        Text(error).font(.caption).textSelection(.enabled).lineLimit(4)
                        Spacer(); Button { state.lastError = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel(L10n.Common.actionCloseNotice)
                    }.padding(14).background(Palette.amber.opacity(0.09))
                }
            }.background(Palette.background)
        }.tint(Palette.cyan).foregroundStyle(Palette.text)
        .sheet(isPresented: $state.showPalette) {
            CommandPalette()
                .environmentObject(state)
                .preferredColorScheme(state.preferredColorScheme)
        }
        .background {
            HostingWindowVisibilityObserver(trackResignKey: false) { visible in
                state.liveMetrics.setWindowVisible(visible, token: windowVisibilityToken)
            }
        }
        .onAppear {
            state.revealWindow = { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
            state.liveMetrics.setWindowVisible(true, token: windowVisibilityToken)
        }
        .onDisappear {
            state.liveMetrics.setWindowVisible(false, token: windowVisibilityToken)
        }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandMark(size: 34)
                Text("brisa").font(.system(size: 25, weight: .semibold, design: .rounded)).tracking(-0.8)
            }.padding(.bottom, 30)

            ForEach(Page.primaryPages) { page in
                sidebarButton(for: page)
                    .padding(.bottom, 4)
            }

            Spacer(minLength: 30)

            Rectangle().fill(Palette.line).frame(height: 1)
                .padding(.bottom, 12)

            sidebarButton(for: .settings)

            HStack { Text("BRISA / 0.1.0"); Spacer(); Text("⌘ K") }
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(Palette.muted.opacity(0.65))
                .padding(.top, 14)
        }.padding(.horizontal, 16).padding(.top, 34).padding(.bottom, 20).frame(width: 205).background(Palette.sidebar)
    }

    private func sidebarButton(for page: Page) -> some View {
        let isSelected = state.page == page
        return Button {
            if page == .findings {
                state.openCleanCandidates()
            } else {
                state.page = page
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: page.icon).font(.system(size: 14)).frame(width: 18)
                Text(page.title).font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                Spacer()
                if page == .findings, !state.eligibleFiles.isEmpty {
                    Text("\(state.eligibleFiles.count)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.mint)
                }
            }
            .foregroundStyle(isSelected ? Palette.cyan : Palette.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(isSelected ? Palette.cyan.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("nav." + page.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    var topbar: some View {
        HStack {
            HStack(spacing: 7) { Image(systemName: "laptopcomputer"); Text(state.computerName).lineLimit(1) }.font(.system(size: 11)).foregroundStyle(Palette.muted)
            Spacer()
            Button { state.showPalette = true } label: {
                HStack(spacing: 12) { Image(systemName: "magnifyingglass"); Text(L10n.Activity.paletteFindCommand); Text("⌘ K").foregroundStyle(.tertiary) }.font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.horizontal, 11).padding(.vertical, 7).background(Palette.surfaceFill, in: RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain)
        }.padding(.horizontal, 30).frame(height: 65).overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
}

struct WelcomeView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                HStack(alignment: .center, spacing: 28) {
                    VStack(alignment: .leading, spacing: 18) {
                        BrandMark(size: 56)
                        SectionHeading(eyebrow: L10n.Activity.onboardingEyebrow, title: L10n.Activity.onboardingTitle, subtitle: L10n.Activity.onboardingSubtitle)
                    }
                    Spacer(minLength: 12)
                    BrandIllustrationView(kind: .welcome)
                        .frame(width: 280, height: 158)
                }
                Card {
                    VStack(alignment: .leading, spacing: 22) {
                        intro("chart.bar.xaxis", L10n.Activity.onboardingCard1Title, L10n.Activity.onboardingCard1Detail)
                        intro("hand.raised", L10n.Activity.onboardingCard2Title, L10n.Activity.onboardingCard2Detail)
                        intro("lock.shield", L10n.Activity.onboardingCard3Title, L10n.Activity.onboardingCard3Detail)
                        intro("sparkles", L10n.Activity.onboardingCard4Title, L10n.Activity.onboardingCard4Detail)
                    }
                }
                HStack {
                    Text(L10n.Activity.onboardingHint).font(.caption).foregroundStyle(Palette.muted).frame(maxWidth: 430, alignment: .leading)
                    Spacer()
                    Button { state.completeWelcome() } label: { Label(L10n.Activity.onboardingStart, systemImage: "arrow.right").padding(6) }.buttonStyle(.borderedProminent)
                }
            }.padding(40).frame(maxWidth: 850).frame(maxWidth: .infinity)
        }
    }
    func intro(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Palette.cyan).frame(width: 25)
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline); Text(detail).font(.callout).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

struct CommandPalette: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    @State private var search = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack { Image(systemName: "magnifyingglass").foregroundStyle(Palette.cyan); TextField(L10n.Activity.palettePlaceholder, text: $search).textFieldStyle(.plain).focused($focused); Button("Esc") { dismiss() }.keyboardShortcut(.cancelAction) }.padding(10)
            Divider()
            ForEach(Page.allCases.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { page in
                Button {
                    if page == .findings {
                        state.openCleanCandidates()
                    } else {
                        state.page = page
                    }
                    dismiss()
                } label: { Label(page.title, systemImage: page.icon).frame(maxWidth: .infinity, alignment: .leading).padding(9) }.buttonStyle(.plain)
            }
            if !search.isEmpty {
                if L10n.Overview.tasksExploreTitle.localizedCaseInsensitiveContains(search) {
                    Button { state.openExploreSpace(); dismiss() } label: { Label(L10n.Overview.tasksExploreTitle, systemImage: "externaldrive").frame(maxWidth: .infinity, alignment: .leading).padding(9) }.buttonStyle(.plain)
                }
                if L10n.Overview.tasksDuplicatesTitle.localizedCaseInsensitiveContains(search) {
                    Button { state.openDuplicates(); dismiss() } label: { Label(L10n.Overview.tasksDuplicatesTitle, systemImage: "square.on.square").frame(maxWidth: .infinity, alignment: .leading).padding(9) }.buttonStyle(.plain)
                }
                if L10n.Overview.tasksAdvancedTitle.localizedCaseInsensitiveContains(search) {
                    Button { state.openAdvancedTools(.projects); dismiss() } label: { Label(L10n.Overview.tasksAdvancedTitle, systemImage: "wrench.and.screwdriver").frame(maxWidth: .infinity, alignment: .leading).padding(9) }.buttonStyle(.plain)
                }
            }
            if search.isEmpty || L10n.Activity.paletteAnalyze.localizedCaseInsensitiveContains(search) {
                Button { do { try state.startScan(); dismiss() } catch { state.fail(error) } } label: { Label(L10n.Activity.paletteAnalyzeStorage, systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity, alignment: .leading).padding(9) }.buttonStyle(.plain).disabled(state.scanning || state.operating)
            }
            if !search.isEmpty {
                ForEach(state.categories.filter { storageCategoryTitle($0.category).localizedCaseInsensitiveContains(search) }) { report in
                    Button { state.openCategory(report.category); dismiss() } label: {
                        Label(storageCategoryTitle(report.category), systemImage: report.category.icon)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(9)
                    }.buttonStyle(.plain)
                }
                ForEach(state.applications.filter { $0.name.localizedCaseInsensitiveContains(search) }.prefix(6)) { app in
                    Button { NSWorkspace.shared.open(app.url); dismiss() } label: { Label(app.name, systemImage: "app").frame(maxWidth: .infinity, alignment: .leading).padding(9) }.buttonStyle(.plain)
                }
            }
            Text(L10n.Activity.paletteHint).font(.caption).foregroundStyle(Palette.muted).padding(.top, 10)
        }.padding(20).frame(width: 540).background(Palette.background).foregroundStyle(Palette.text).onAppear { focused = true; state.loadApplications() }
    }
}
