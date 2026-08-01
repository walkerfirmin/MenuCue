import AppKit
import KeyboardShortcuts

/// Registers the global palette hotkey

enum HotkeyController {
    private static var globalMonitor: Any?
    private static var localMonitor: Any?
    private static var lastFire = Date.distantPast
    private static var observersInstalled = false

    static func start() {
        _ = KeyboardShortcuts.Name.togglePalette
        resolveConflictIfNeeded()

        let shortcut = KeyboardShortcuts.getShortcut(for: .togglePalette)
        MenuCueLog.hotkey.info("Active shortcut=\(String(describing: shortcut), privacy: .public)")

        KeyboardShortcuts.onKeyDown(for: .togglePalette) {
            fire(source: "KeyboardShortcuts")
        }

        installEventMonitors()
        installWorkspaceObservers()
    }

    private static func fire(source: String) {
        let now = Date()
        guard now.timeIntervalSince(lastFire) > 0.25 else { return }
        lastFire = now
        MenuCueDebug.log("hotkey fired via \(source)")
        MenuCueLog.hotkey.info("Hotkey fired via \(source, privacy: .public)")
        DispatchQueue.main.async {
            PaletteController.shared.toggle()
        }
    }

    private static func resolveConflictIfNeeded() {
        let conflicting = conflictingAppsRunning()
        guard !conflicting.isEmpty else { return }

        let current = KeyboardShortcuts.getShortcut(for: .togglePalette)
        let shiftCmdP = KeyboardShortcuts.Shortcut(.p, modifiers: [.command, .shift])
        let optionCmdP = KeyboardShortcuts.Shortcut(.p, modifiers: [.command, .option])

        if current == nil || current == shiftCmdP {
            KeyboardShortcuts.setShortcut(optionCmdP, for: .togglePalette)
            MenuCueLog.hotkey.warning(
                "⇧⌘P taken by \(conflicting.joined(separator: ", "), privacy: .public); remapped to ⌥⌘P"
            )
        }
    }

    private static func conflictingAppsRunning() -> [String] {
        let conflictBundleIDs: Set<String> = [
            "com.example.CMD-Palette"
        ]
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier, conflictBundleIDs.contains(id) else { return nil }
            return app.localizedName ?? id
        }
    }

    private static func installWorkspaceObservers() {
        guard !observersInstalled else { return }
        observersInstalled = true
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            resolveConflictIfNeeded()
            installEventMonitors()
        }
        center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            installEventMonitors()
        }
    }

    private static func installEventMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard matches(event) else { return }
            fire(source: "NSEventGlobal")
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard matches(event) else { return event }
            fire(source: "NSEventLocal")
            return nil
        }
    }

    private static func matches(_ event: NSEvent) -> Bool {
        guard !event.isARepeat else { return false }
        guard let wanted = KeyboardShortcuts.getShortcut(for: .togglePalette) else { return false }
        guard Int(event.keyCode) == wanted.carbonKeyCode else { return false }
        let eventMods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        return eventMods == wanted.modifiers.intersection([.command, .shift, .option, .control])
    }
}
