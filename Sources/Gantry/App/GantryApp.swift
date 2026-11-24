import AppKit
import SwiftUI

@main
struct GantryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var app = AppModel()

    var body: some Scene {
        Window("Gantry", id: "main") {
            RootView()
                .environment(app)
                .onAppear {
                    appDelegate.model = app
                }
        }
        .defaultSize(width: 1240, height: 840)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            AppCommands(app: app)
        }

        MenuBarExtra {
            MenuBarView()
                .environment(app)
                .preferredColorScheme(app.appearance.colorScheme)
        } label: {
            MenuBarStatusLabel(app: app) {
                appDelegate.model = app
                app.start()
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(app)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Kept for termination after the main window has been closed. The model
    /// lives at app scope, not window scope, so background turns keep running.
    var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep the app alive and out of the way. The menu bar extra remains
        // visible and can restore the window or handle requests.
        DispatchQueue.main.async {
            NSApp.hide(nil)
        }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.shutdown()
    }

    /// The Dock icon should bring Gantry back after its window was closed.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard !flag else { return true }
        NSApp.unhide(nil)
        if let window = NSApp.windows.first(where: { $0.title == "Gantry" }) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        // SwiftUI owns the Window scene; the menu bar label listens for this
        // and reopens it when there is no window object left to order front.
        NotificationCenter.default.post(name: .gantryShowMainWindow, object: nil)
        return true
    }
}

extension Notification.Name {
    static let gantryShowMainWindow = Notification.Name("GantryShowMainWindow")
}
