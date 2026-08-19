import AppKit
import SwiftUI

private enum RepoManagerWindowMetrics {
    static let aspectRatio = NSSize(width: 16, height: 10)
    static let minContentSize = NSSize(width: 600, height: 420)
    static let readableFloor = NSSize(width: 960, height: 600)

    static func defaultContentSize(for screen: NSScreen? = NSScreen.main) -> NSSize {
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let boxW = visible.width / 2
        let boxH = visible.height / 2

        // Largest 16:10 rect inside half-screen box.
        var width = boxW
        var height = width * aspectRatio.height / aspectRatio.width
        if height > boxH {
            height = boxH
            width = height * aspectRatio.width / aspectRatio.height
        }

        // Scale up to readable floor while preserving 16:10.
        let scaleW = readableFloor.width / width
        let scaleH = readableFloor.height / height
        if scaleW > 1 || scaleH > 1 {
            let scale = max(scaleW, scaleH)
            width *= scale
            height *= scale
        }

        // Enforce absolute minimums (scale up uniformly).
        let minScaleW = minContentSize.width / width
        let minScaleH = minContentSize.height / height
        if minScaleW > 1 || minScaleH > 1 {
            let scale = max(minScaleW, minScaleH)
            width *= scale
            height *= scale
        }

        // Cap to visible frame (preserve aspect ratio).
        if width > visible.width || height > visible.height {
            let capW = visible.width / width
            let capH = visible.height / height
            let scale = min(capW, capH)
            width *= scale
            height *= scale
        }

        return NSSize(width: floor(width), height: floor(height))
    }

    static func centerFrame(contentSize: NSSize, on screen: NSScreen? = NSScreen.main) -> NSRect {
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = visible.midX - contentSize.width / 2
        let y = visible.midY - contentSize.height / 2
        return NSRect(x: floor(x), y: floor(y), width: contentSize.width, height: contentSize.height)
    }

    static func applyContentSize(_ size: NSSize, to window: NSWindow) {
        window.setContentSize(size)
        window.updateConstraintsIfNeeded()
    }
}

@MainActor
final class RepoManagerController: ObservableObject {
    static let shared = RepoManagerController()

    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let screen = NSScreen.main
        let contentSize = RepoManagerWindowMetrics.defaultContentSize(for: screen)
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let root = RepoManagerView()
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = []

        let window = NSWindow(
            contentRect: RepoManagerWindowMetrics.centerFrame(contentSize: contentSize, on: screen),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Quick Action Repo Manager"
        window.contentViewController = hosting
        window.contentAspectRatio = RepoManagerWindowMetrics.aspectRatio
        window.contentMinSize = RepoManagerWindowMetrics.minContentSize
        window.contentMaxSize = NSSize(width: visible.width, height: visible.height)
        RepoManagerWindowMetrics.applyContentSize(contentSize, to: window)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window

        // Re-apply after hosting layout; SwiftUI can shrink on first pass.
        DispatchQueue.main.async {
            RepoManagerWindowMetrics.applyContentSize(contentSize, to: window)
        }
    }
}
