import AppKit
import SwiftUI

@MainActor
final class RepoManagerController: ObservableObject {
    static let shared = RepoManagerController()

    private var window: NSWindow?

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = RepoManagerView()
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 2600, height: 1726),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Quick Action Repo Manager"
        window.contentViewController = hosting
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 2600, height: 1726)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
