import AppKit
import SwiftUI

/// Observes the backing `NSWindow`/`NSPanel` visibility directly so SwiftUI surfaces
/// (including `MenuBarExtra(.window)` and closable macOS windows) report hide/close reliably
/// even when AppKit orders a window out without tearing down the SwiftUI view hierarchy.
struct HostingWindowVisibilityObserver: NSViewRepresentable {
    let trackResignKey: Bool
    let onVisibilityChange: @MainActor (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(trackResignKey: trackResignKey, onVisibilityChange: onVisibilityChange)
    }

    func makeNSView(context: Context) -> ObserverNSView {
        let view = ObserverNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: ObserverNSView, context: Context) {
        context.coordinator.trackResignKey = trackResignKey
        context.coordinator.onVisibilityChange = onVisibilityChange
        context.coordinator.attach(to: nsView.window, deferPublish: true)
    }

    static func dismantleNSView(_ nsView: ObserverNSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class ObserverNSView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.coordinator?.attach(to: self.window, deferPublish: false)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var trackResignKey: Bool
        var onVisibilityChange: @MainActor (Bool) -> Void
        private weak var observedWindow: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var visibleObservation: NSKeyValueObservation?
        private var resignKeyTask: Task<Void, Never>?
        private var lastReported: Bool?

        init(trackResignKey: Bool, onVisibilityChange: @escaping @MainActor (Bool) -> Void) {
            self.trackResignKey = trackResignKey
            self.onVisibilityChange = onVisibilityChange
        }

        func attach(to window: NSWindow?, deferPublish: Bool) {
            if observedWindow !== window {
                clearObservers()
                observedWindow = window
                if let window {
                    let center = NotificationCenter.default
                    let names: [Notification.Name] = [
                        NSWindow.willCloseNotification,
                        NSWindow.didChangeOcclusionStateNotification,
                        NSWindow.didMiniaturizeNotification,
                        NSWindow.didDeminiaturizeNotification,
                        NSWindow.didBecomeKeyNotification,
                        NSWindow.didResignKeyNotification
                    ]
                    for name in names {
                        let token = center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                            Task { @MainActor [weak self] in
                                self?.handleWindowNotification(name)
                            }
                        }
                        observers.append(token)
                    }
                    visibleObservation = window.observe(\.isVisible, options: [.new]) { [weak self, weak window] _, _ in
                        Task { @MainActor [weak self, weak window] in
                            self?.evaluate(window: window, resigningKey: false)
                        }
                    }
                }
            }

            if deferPublish {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.evaluate(window: self.observedWindow, resigningKey: false)
                }
            } else {
                evaluate(window: window, resigningKey: false)
            }
        }

        func detach() {
            clearObservers()
            observedWindow = nil
            Task { @MainActor [weak self] in
                self?.publish(false)
            }
        }

        private func handleWindowNotification(_ name: Notification.Name) {
            if name == NSWindow.willCloseNotification {
                resignKeyTask?.cancel()
                publish(false)
            } else if name == NSWindow.didBecomeKeyNotification {
                resignKeyTask?.cancel()
                evaluate(window: observedWindow, resigningKey: false)
            } else if name == NSWindow.didResignKeyNotification, trackResignKey {
                resignKeyTask?.cancel()
                resignKeyTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    guard let self, !Task.isCancelled else { return }
                    self.evaluate(window: self.observedWindow, resigningKey: true)
                }
            } else {
                evaluate(window: observedWindow, resigningKey: name == NSWindow.didResignKeyNotification)
            }
        }

        private func evaluate(window: NSWindow?, resigningKey: Bool) {
            guard let window else {
                publish(false)
                return
            }
            if trackResignKey && resigningKey {
                let hasChildPopover = !(window.childWindows?.isEmpty ?? true)
                if !hasChildPopover && !window.isKeyWindow {
                    publish(false)
                    return
                }
            }
            let visible = window.isVisible
                && !window.isMiniaturized
                && window.occlusionState.contains(.visible)
            publish(visible)
        }

        private func publish(_ visible: Bool) {
            guard lastReported != visible else { return }
            lastReported = visible
            onVisibilityChange(visible)
        }

        private func clearObservers() {
            resignKeyTask?.cancel()
            resignKeyTask = nil
            visibleObservation?.invalidate()
            visibleObservation = nil
            let center = NotificationCenter.default
            for token in observers {
                center.removeObserver(token)
            }
            observers.removeAll()
        }
    }
}
