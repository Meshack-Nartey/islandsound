import AppKit
import SwiftUI
import Combine

/// Owns the borderless, always-on-top `NSPanel` the island renders in.
///
/// Implements the Island Window Rules from Section 11.2:
/// - `.borderless` style, `.nonactivatingPanel`, level = `.statusBar + 1`
/// - positioned at `screen.frame.midX - width/2`, anchored to the notch
/// - never activates the app / steals focus from the front app
/// - click-through (mouse events pass to whatever is behind the island)
///   while collapsed; only intercepts events while expanded or full screen
@MainActor
final class IslandWindowController: NSObject {
    private var panel: NSPanel!
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()

    /// The app that was frontmost before the full-screen "drop" took key
    /// status (so its keyboard focus can be restored once the drop closes).
    private var previouslyActiveApp: NSRunningApplication?

    init(appState: AppState) {
        self.appState = appState
        super.init()
        setupPanel()
        observeState()
        layout(for: appState.islandState, animated: false)
    }

    // MARK: - Setup

    private func setupPanel() {
        let panel = IslandPanel(
            contentRect: NSRect(origin: .zero, size: IslandMetrics.collapsedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = false

        let hosting = NSHostingView(rootView: IslandView(appState: appState))
        hosting.frame = NSRect(origin: .zero, size: IslandMetrics.collapsedSize)
        panel.contentView = hosting

        self.panel = panel
        panel.orderFrontRegardless()
    }

    private func observeState() {
        appState.$islandState
            .removeDuplicates()
            .sink { [weak self] state in
                self?.layout(for: state, animated: true)
            }
            .store(in: &cancellables)
    }

    // MARK: - Layout

    private func layout(for state: IslandState, animated: Bool) {
        let size = size(for: state)
        let frame = frame(for: size, state: state)

        // Click-through: only intercept mouse events when the island is
        // showing controls (expanded/full screen). Collapsed pill lets
        // clicks pass straight through to whatever is behind the notch.
        panel.ignoresMouseEvents = (state == .collapsed)

        // The full-screen "drop" contains a text field (room code entry),
        // which needs the panel to be key to receive keystrokes. Make it
        // key explicitly (see `IslandPanel.canBecomeKey` below), and hand
        // focus back to whatever app was frontmost once the drop closes.
        if state == .fullScreen {
            if previouslyActiveApp == nil {
                previouslyActiveApp = NSWorkspace.shared.frontmostApplication
            }
            panel.makeKeyAndOrderFront(nil)
        } else if let previousApp = previouslyActiveApp {
            previouslyActiveApp = nil
            previousApp.activate()
        }

        if let hosting = panel.contentView as? NSHostingView<IslandView> {
            hosting.rootView = IslandView(appState: appState)
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = IslandMetrics.transition.response
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }

        panel.contentView?.setFrameSize(size)
    }

    private func size(for state: IslandState) -> CGSize {
        switch state {
        case .collapsed: return IslandMetrics.collapsedSize
        case .expanded: return IslandMetrics.expandedSize
        case .fullScreen: return IslandMetrics.fullScreenSize
        }
    }

    /// Computes the panel's frame, horizontally centred on the screen, per
    /// Section 11.2's position formula: `x = screen.frame.midX - width/2`.
    ///
    /// Vertically:
    /// - `.collapsed` sits flush against the very top of the screen
    ///   (`y = screen.frame.maxY - height`), straddling the camera housing.
    ///   `collapsedSize` is wide enough that its content sits either side of
    ///   the housing rather than behind it (matching the "notch pill" look
    ///   of other menu-bar music widgets).
    /// - `.expanded`/`.fullScreen` ("the drop") sit just *below* the camera
    ///   housing (`y = screen.frame.maxY - safeAreaInsets.top - height`), so
    ///   the larger panel's artwork/text are never obscured by the camera.
    ///   On non-notched screens `safeAreaInsets.top` is 0, equivalent to
    ///   flush-top.
    private func frame(for size: CGSize, state: IslandState) -> NSRect {
        let screen = targetScreen
        let x = screen.frame.midX - size.width / 2
        let topInset = (state == .collapsed) ? 0 : screen.safeAreaInsets.top
        let y = screen.frame.maxY - topInset - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// The screen containing the built-in display (and notch) when present,
    /// falling back to the main screen on external-display-only setups.
    private var targetScreen: NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

/// A borderless `NSPanel` can normally become key, but in practice a
/// `.statusBar`-level `.nonactivatingPanel` owned by an `.accessory` app
/// doesn't reliably do so via `makeKeyAndOrderFront` alone. Overriding
/// `canBecomeKey` removes any ambiguity so the panel's `TextField`
/// (room code entry) can become first responder and accept keystrokes.
private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
