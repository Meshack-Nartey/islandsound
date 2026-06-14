import SwiftUI
import AppKit

@main
struct IslandSoundApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // IslandSound has no conventional window -- the entire UI lives in
        // the borderless `NSPanel` owned by `IslandWindowController`. SwiftUI
        // requires at least one `Scene`, so an empty `Settings` scene stands
        // in; it is never shown (Section 11.2).
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: IslandWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let appState = AppState.shared
        windowController = IslandWindowController(appState: appState)
        appState.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
