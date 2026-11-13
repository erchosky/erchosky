import SwiftUI
import AppKit
import BrisaCore

/// Metric refreshes invalidate only the widgets that observe this store.
@MainActor final class LiveMetricsStore: ObservableObject {
    @Published private(set) var snapshot: MetricsSnapshot?
    @Published private(set) var breakdown: HardwareBreakdownSnapshot?

    private let sampler: MetricsSampler
    private let breakdownSampler: LiveHardwareBreakdownSampler
    private var inFlight: Task<MetricsSnapshot, Never>?
    private var inFlightForceSnapshots = false
    private var breakdownInFlight: Task<HardwareBreakdownSnapshot, Never>?
    private var refreshTask: Task<Void, Never>?
    private var breakdownRefreshTask: Task<Void, Never>?
    private var warmupRetryTask: Task<Void, Never>?
    private var timer: Timer?
    private var breakdownTimer: Timer?
    private var statusBarTimer: Timer?
    private var statusBarMonitoring = false

    private var menuTokens: Set<UUID> = []
    private var windowTokens: Set<UUID> = []
    private var menuBreakdownNeeded = true
    private var appHidden = false
    private var systemAsleep = false
    private var isShutdown = false
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    var isMenuVisible: Bool { !menuTokens.isEmpty }
    var isWindowPollingActive: Bool { timer != nil }
    var isBreakdownPollingActive: Bool { breakdownTimer != nil }
    var isStatusBarPollingActive: Bool { statusBarTimer != nil }

    init(observeLifecycle: Bool = true) {
        let sharedSampler = MetricsSampler()
        self.sampler = sharedSampler
        self.breakdownSampler = LiveHardwareBreakdownSampler(metricsSampler: sharedSampler)
        if observeLifecycle {
            registerLifecycleObservers()
        }
    }

    /// Stops all timers, observers, and in-flight telemetry tasks cleanly.
    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        stopAllPolling(cancelInFlight: true, resetBaseline: true)
        let nc = NotificationCenter.default
        for token in lifecycleObservers { nc.removeObserver(token) }
        lifecycleObservers.removeAll()
        let ws = NSWorkspace.shared.notificationCenter
        for token in workspaceObservers { ws.removeObserver(token) }
        workspaceObservers.removeAll()
    }

    func refresh(forceSnapshots: Bool = false) {
        guard !isShutdown else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.sample(maxAge: 0, forceSnapshots: forceSnapshots)
        }
    }

    @discardableResult func sample(maxAge: TimeInterval = 3, forceSnapshots: Bool = false) async -> MetricsSnapshot {
        if !forceSnapshots, let snapshot, Date().timeIntervalSince(snapshot.date) < maxAge { return snapshot }
        while let current = inFlight {
            let wasForced = inFlightForceSnapshots
            let existingResult = await current.value
            if inFlight == current {
                inFlight = nil
                inFlightForceSnapshots = false
            }
            if !Task.isCancelled, snapshot == nil || existingResult.date >= snapshot!.date {
                snapshot = existingResult
            }
            if !forceSnapshots || wasForced || Task.isCancelled {
                return existingResult
            }
        }
        let sampler = self.sampler
        let task = Task.detached(priority: .utility) { sampler.sample(forceRefreshSnapshots: forceSnapshots) }
        inFlight = task
        inFlightForceSnapshots = forceSnapshots
        let result = await task.value
        if inFlight == task {
            inFlight = nil
            inFlightForceSnapshots = false
        }
        if !Task.isCancelled, snapshot == nil || result.date >= snapshot!.date {
            snapshot = result
        }
        return result
    }

    func setWindowVisible(_ visible: Bool, token: UUID = LiveMetricsStore.defaultWindowToken) {
        guard !isShutdown else { return }
        if visible {
            windowTokens.insert(token)
        } else {
            windowTokens.remove(token)
        }
        reconcilePollingState(triggerImmediateRefresh: visible)
    }

    /// The optional free-space label remains visible even when the window and popover are closed.
    func setStatusBarMonitoring(_ enabled: Bool) {
        guard !isShutdown else { return }
        statusBarMonitoring = enabled
        reconcilePollingState(triggerImmediateRefresh: enabled)
    }

    func setMenuVisible(_ visible: Bool, token: UUID = LiveMetricsStore.defaultMenuToken, breakdownNeeded: Bool? = nil) {
        guard !isShutdown else { return }
        if visible {
            menuTokens.insert(token)
        } else {
            menuTokens.remove(token)
        }
        if let breakdownNeeded {
            menuBreakdownNeeded = breakdownNeeded
        }
        reconcilePollingState(triggerImmediateRefresh: visible)
    }

    func setMenuBreakdownNeeded(_ needed: Bool) {
        guard !isShutdown, menuBreakdownNeeded != needed else { return }
        menuBreakdownNeeded = needed
        reconcilePollingState(triggerImmediateRefresh: needed && isMenuVisible)
    }

    nonisolated private static let defaultWindowToken = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    nonisolated private static let defaultMenuToken = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    private var hasVisibleMainWindow: Bool {
        if !windowTokens.isEmpty {
            // Also require non-miniaturized/visible status when AppKit windows exist.
            if NSApp != nil, !NSApp.windows.isEmpty {
                return NSApp.windows.contains {
                    $0.isVisible && !$0.isMiniaturized && $0.frame.width >= 200 && $0.frame.height >= 100
                }
            }
            return true
        }
        return false
    }

    private func reconcilePollingState(triggerImmediateRefresh: Bool) {
        guard !isShutdown, !systemAsleep else {
            stopAllPolling(cancelInFlight: true, resetBaseline: false)
            return
        }

        if isMenuVisible && menuBreakdownNeeded {
            // Menu performance expanded on Home: 2s breakdown polling updates both snapshot and breakdown.
            stopWindowPolling(cancelInFlight: false)
            stopStatusBarPolling()
            startBreakdownPollingIfNeeded(triggerImmediate: triggerImmediateRefresh)
            return
        }

        stopBreakdownPolling()

        if !appHidden && (hasVisibleMainWindow || isMenuVisible) {
            stopStatusBarPolling()
            startWindowPollingIfNeeded(triggerImmediate: triggerImmediateRefresh)
        } else {
            stopWindowPolling(cancelInFlight: true)
            breakdownSampler.resetBaseline()
            if statusBarMonitoring {
                startStatusBarPollingIfNeeded(triggerImmediate: triggerImmediateRefresh)
            } else {
                stopStatusBarPolling()
            }
        }
    }

    private func startStatusBarPollingIfNeeded(triggerImmediate: Bool) {
        if triggerImmediate { refresh() }
        guard statusBarTimer == nil else { return }
        let scheduled = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isShutdown, !self.systemAsleep, self.statusBarMonitoring else { return }
                self.refresh()
            }
        }
        scheduled.tolerance = 5
        RunLoop.main.add(scheduled, forMode: .common)
        statusBarTimer = scheduled
    }

    private func stopStatusBarPolling() {
        statusBarTimer?.invalidate()
        statusBarTimer = nil
    }

    private func startWindowPollingIfNeeded(triggerImmediate: Bool) {
        if triggerImmediate {
            refresh()
        }
        guard timer == nil else { return }
        let scheduled = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isShutdown, !self.appHidden, !self.systemAsleep, !(self.isMenuVisible && self.menuBreakdownNeeded) else { return }
                guard self.hasVisibleMainWindow || self.isMenuVisible else {
                    self.reconcilePollingState(triggerImmediateRefresh: false)
                    return
                }
                self.refresh()
            }
        }
        scheduled.tolerance = 0.5
        timer = scheduled
    }

    private func stopWindowPolling(cancelInFlight: Bool) {
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
        if cancelInFlight {
            inFlight?.cancel()
            inFlight = nil
            inFlightForceSnapshots = false
        }
    }

    private func startBreakdownPollingIfNeeded(triggerImmediate: Bool) {
        if triggerImmediate {
            refreshBreakdown()
        }
        guard breakdownTimer == nil else { return }
        let scheduled = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isShutdown, !self.systemAsleep, self.isMenuVisible, self.menuBreakdownNeeded else { return }
                self.refreshBreakdown()
            }
        }
        scheduled.tolerance = 0.3
        breakdownTimer = scheduled
    }

    private func stopBreakdownPolling() {
        breakdownTimer?.invalidate()
        breakdownTimer = nil
        warmupRetryTask?.cancel()
        warmupRetryTask = nil
        breakdownRefreshTask?.cancel()
        breakdownRefreshTask = nil
        breakdownInFlight?.cancel()
        breakdownInFlight = nil
        breakdownSampler.resetBaseline()
    }

    private func stopAllPolling(cancelInFlight: Bool, resetBaseline: Bool) {
        stopStatusBarPolling()
        stopBreakdownPolling()
        stopWindowPolling(cancelInFlight: cancelInFlight)
        if resetBaseline {
            breakdownSampler.resetBaseline()
        }
    }

    private func registerLifecycleObservers() {
        let nc = NotificationCenter.default
        let ws = NSWorkspace.shared.notificationCenter

        lifecycleObservers.append(
            nc.addObserver(forName: NSApplication.didHideNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.appHidden = true
                    self?.reconcilePollingState(triggerImmediateRefresh: false)
                }
            }
        )
        lifecycleObservers.append(
            nc.addObserver(forName: NSApplication.didUnhideNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.appHidden = false
                    self?.reconcilePollingState(triggerImmediateRefresh: true)
                }
            }
        )
        for name in [NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
            lifecycleObservers.append(
                nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.reconcilePollingState(triggerImmediateRefresh: name == NSWindow.didDeminiaturizeNotification)
                    }
                }
            )
        }
        workspaceObservers.append(
            ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.systemAsleep = true
                    self?.stopAllPolling(cancelInFlight: true, resetBaseline: true)
                }
            }
        )
        workspaceObservers.append(
            ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.systemAsleep = false
                    self?.breakdownSampler.resetBaseline()
                    self?.reconcilePollingState(triggerImmediateRefresh: true)
                }
            }
        )
    }

    func refreshBreakdown() {
        guard !isShutdown else { return }
        breakdownRefreshTask?.cancel()
        breakdownRefreshTask = Task { [weak self] in
            await self?.sampleBreakdown()
        }
    }

    @discardableResult func sampleBreakdown() async -> HardwareBreakdownSnapshot {
        if let breakdownInFlight {
            return await breakdownInFlight.value
        }
        let sampler = self.breakdownSampler
        let systemLabel = L10n.MenuBar.breakdownSystemLabel
        let otherLabel = L10n.MenuBar.breakdownOtherLabel

        let task = Task.detached(priority: .utility) {
            sampler.sample(otherLabel: otherLabel, systemLabel: systemLabel)
        }
        breakdownInFlight = task
        let result = await task.value
        if breakdownInFlight == task {
            breakdownInFlight = nil
        }

        // Discard late results after cancellation or closing the menu popover.
        guard !Task.isCancelled, !isShutdown, isMenuVisible, menuBreakdownNeeded else {
            return result
        }

        if breakdown == nil || result.sampledAt >= breakdown!.sampledAt {
            breakdown = result
        }

        var mergedMetrics = result.metrics
        if mergedMetrics.localSnapshots == nil, let existing = snapshot?.localSnapshots {
            mergedMetrics.localSnapshots = existing
        }
        if snapshot == nil || mergedMetrics.date >= snapshot!.date {
            snapshot = mergedMetrics
        }

        // First sample seeds GPU cumulative counters; take one bounded follow-up while menu remains visible.
        if result.gpuStatus == .warmingUp && isMenuVisible && menuBreakdownNeeded {
            warmupRetryTask?.cancel()
            warmupRetryTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 550_000_000)
                guard let self, !Task.isCancelled, !self.isShutdown, self.isMenuVisible, self.menuBreakdownNeeded, self.breakdown?.gpuStatus == .warmingUp else { return }
                self.refreshBreakdown()
            }
        } else {
            warmupRetryTask?.cancel()
            warmupRetryTask = nil
        }
        return result
    }

    deinit {
        statusBarTimer?.invalidate()
        timer?.invalidate()
        breakdownTimer?.invalidate()
        warmupRetryTask?.cancel()
        refreshTask?.cancel()
        breakdownRefreshTask?.cancel()
        inFlight?.cancel()
        breakdownInFlight?.cancel()
    }
}

struct LiveMetricsRegion<Content: View>: View {
    @ObservedObject var store: LiveMetricsStore
    @ViewBuilder let content: (MetricsSnapshot?) -> Content
    var body: some View { content(store.snapshot) }
}

@MainActor final class AppIconCache {
    static let shared = AppIconCache()
    private static let displayPoints = 44
    private static let pixelDimension = 88
    private static let maxConcurrentLoads = 3

    private final class SlotWaiter: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Bool, Never>?
        private var resolved = false

        func setContinuation(_ continuation: CheckedContinuation<Bool, Never>) {
            let resumeImmediately: Bool = lock.withLock {
                if resolved {
                    return true
                }
                self.continuation = continuation
                return false
            }
            if resumeImmediately {
                continuation.resume(returning: false)
            }
        }

        @discardableResult
        func tryResume(with value: Bool) -> Bool {
            let cont: CheckedContinuation<Bool, Never>? = lock.withLock {
                guard !resolved else { return nil }
                resolved = true
                let existing = continuation
                continuation = nil
                return existing
            }
            guard let cont else { return false }
            cont.resume(returning: value)
            return true
        }
    }

    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 128
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    private var activeLoads = 0
    private var waiters: [SlotWaiter] = []

    func cachedIcon(forBundlePath path: String) -> NSImage? {
        cache.object(forKey: path as NSString)
    }

    func icon(forBundlePath path: String) -> NSImage {
        if let existing = cachedIcon(forBundlePath: path) {
            return existing
        }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: Self.displayPoints, height: Self.displayPoints)
        cache.setObject(image, forKey: path as NSString, cost: Self.pixelDimension * Self.pixelDimension * 4)
        return image
    }

    func loadIcon(forBundlePath path: String) async -> NSImage? {
        if let existing = cachedIcon(forBundlePath: path) {
            return existing
        }
        guard !Task.isCancelled else { return nil }
        let acquired = await acquireSlot()
        guard acquired else { return nil }
        defer { releaseSlot() }

        guard !Task.isCancelled else { return nil }
        if let existing = cachedIcon(forBundlePath: path) {
            return existing
        }

        let targetPx = Self.pixelDimension
        let cgImage: CGImage? = await Task.detached(priority: .utility) {
            Self.rasterizeSmallIcon(forBundlePath: path, pixelDimension: targetPx)
        }.value

        guard !Task.isCancelled, let cgImage else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: Self.displayPoints, height: Self.displayPoints))
        let cost = max(1, cgImage.width * cgImage.height * 4)
        cache.setObject(image, forKey: path as NSString, cost: cost)
        return image
    }

    private func acquireSlot() async -> Bool {
        if Task.isCancelled { return false }
        if activeLoads < Self.maxConcurrentLoads {
            activeLoads += 1
            return true
        }
        let waiter = SlotWaiter()
        waiters.append(waiter)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiter.setContinuation(continuation)
            }
        } onCancel: {
            waiter.tryResume(with: false)
        }
    }

    private func releaseSlot() {
        while !waiters.isEmpty {
            let next = waiters.removeFirst()
            if next.tryResume(with: true) {
                return
            }
        }
        activeLoads = max(0, activeLoads - 1)
    }

    nonisolated private static func rasterizeSmallIcon(forBundlePath path: String, pixelDimension: Int) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: path)
        var proposedRect = NSRect(x: 0, y: 0, width: pixelDimension, height: pixelDimension)
        guard let source = icon.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }
        if source.width <= pixelDimension && source.height <= pixelDimension {
            return source
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? Optional(CGColorSpaceCreateDeviceRGB()),
              let context = CGContext(
                  data: nil,
                  width: pixelDimension,
                  height: pixelDimension,
                  bitsPerComponent: 8,
                  bytesPerRow: pixelDimension * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return source
        }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: pixelDimension, height: pixelDimension))
        return context.makeImage() ?? source
    }
}
