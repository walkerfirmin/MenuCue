import AppKit
import KeyboardShortcuts
import SwiftUI

@main
struct MenuCueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // System-managed menu bar extra — more reliable on macOS Tahoe than a
        // hand-rolled NSStatusItem, and shows up under Menu Bar settings.
        MenuBarExtra("MenuCue", systemImage: "command") {
            Button("Show Palette") {
                Task { @MainActor in
                    PaletteController.shared.show()
                }
            }

            Divider()

            Button("Quick Action Repo Manager…") {
                Task { @MainActor in
                    RepoManagerController.shared.show()
                }
            }

            Button("Preferences…") {
                appDelegate.showSettings()
            }

            Button("Menu Bar Settings…") {
                appDelegate.openMenuBarSettings()
            }

            Divider()

            Button("Quit MenuCue") {
                NSApp.terminate(nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?

    private let settings = SettingsStore.shared
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var updateController: UpdateController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        MenuCueDebug.log("launched AX=\(AccessibilityPermission.isTrusted)")
        MenuCueLog.general.info("MenuCue launched; AX trusted=\(AccessibilityPermission.isTrusted, privacy: .public)")

        // Hide Dock icon. MenuBarExtra still appears in the menu bar.
        NSApp.setActivationPolicy(.accessory)

        setupHotkey()
        PaletteController.shared.start()
        updateController = UpdateController()
        updateController?.start()

        if !AccessibilityPermission.isTrusted {
            MenuCueDebug.log("showing onboarding (AX off)")
            showOnboarding()
        }

        #if DEBUG
        // Skip Tahoe menu-bar nag during debug so it doesn't block the palette.
        #else
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.showMenuBarAllowListGuidanceIfNeeded()
        }
        #endif

        #if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            MenuCueDebug.log("DEBUG auto-show palette")
            // Use main.async (not Task) to avoid Swift concurrency executor issues
            // with MenuBarExtra on macOS Tahoe.
            DispatchQueue.main.async {
                FrontmostAppTracker.shared.start()
                PaletteController.shared.show()
            }
        }
        #endif
    }

    private func setupHotkey() {
        HotkeyController.start()
        MenuCueDebug.log("hotkey setup complete shortcut=\(String(describing: KeyboardShortcuts.getShortcut(for: .togglePalette)))")
    }

    func showSettings() {
        if let settingsWindow, settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = SettingsView()
            .environmentObject(settings)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MenuCue Preferences"
        window.contentViewController = hosting
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    func showOnboarding() {
        if onboardingWindow != nil { return }
        let root = OnboardingView {
            self.closeOnboarding()
        }
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Enable Accessibility"
        window.contentViewController = hosting
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    func closeOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = nil
    }

    func openMenuBarSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.MenuBarSettings",
            "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.dock"
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private func showMenuBarAllowListGuidanceIfNeeded() {
        let defaults = UserDefaults.standard
        let lastShownKey = "hasShownMenuBarAllowListGuidance"
        let showCountKey = "menuBarAllowListGuidanceShowCount"
        let suppressKey = "menuBarAllowListGuidanceSuppressed"

        if defaults.bool(forKey: suppressKey) { return }

        let showCount = defaults.integer(forKey: showCountKey)
        if showCount >= 3 { return }

        // Only prompt once per day, and never more than three times.
        if let last = defaults.object(forKey: lastShownKey) as? Date,
           Date().timeIntervalSince(last) < 24 * 60 * 60 {
            return
        }

        // Heuristic: if we have no on-screen window owned by MenuCue at the
        // status-bar layer, the icon is likely blocked by the allow-list.
        if hasOnScreenStatusBarPresence() { return }

        defaults.set(Date(), forKey: lastShownKey)
        defaults.set(showCount + 1, forKey: showCountKey)

        let alert = NSAlert()
        alert.messageText = "Enable MenuCue in the menu bar"
        alert.informativeText = """
            macOS Tahoe hides new menu bar apps until you allow them.

            Open System Settings → Menu Bar → Allow in the Menu Bar, then turn MenuCue ON.

            You can also use ⌥⌘P anytime to open the palette.
            """
        alert.addButton(withTitle: "Open Menu Bar Settings")
        alert.addButton(withTitle: "Dismiss")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't show again"
        alert.suppressionButton?.state = .off
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            defaults.set(true, forKey: suppressKey)
        }
        if response == .alertFirstButtonReturn {
            openMenuBarSettings()
        }
    }

    private func hasOnScreenStatusBarPresence() -> Bool {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        for window in info {
            let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t
            let layer = window[kCGWindowLayer as String] as? Int ?? -1
            guard ownerPID == pid || layer == 25 else { continue }
            if ownerPID == pid { return true }
            // Control Center hosts some extras; can't attribute easily — fall through.
        }
        // Also treat visible MenuBarExtra as OK if our process owns any window.
        return info.contains { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid }
    }
}
