import ApplicationServices
import AppKit
import Carbon.HIToolbox

enum CommandExecutor {
    enum Result {
        case success
        case failed(String)
    }

    static func execute(_ command: MenuCommand, target: NSRunningApplication) -> Result {
        target.activate(options: [.activateIgnoringOtherApps])

        // Brief delay so the target is frontmost before AX press
        usleep(30_000)

        if command.isExtension, let scriptName = command.extensionScriptName {
            return runExtension(named: scriptName)
        }

        if let element = command.element {
            let enabled = AXHelper.boolValue(element, kAXEnabledAttribute as String) ?? true
            if !enabled {
                return .failed("Command is disabled")
            }
            let err = AXUIElementPerformAction(element, kAXPressAction as CFString)
            if err == .success {
                return .success
            }
        }

        // Fallback: synthesize shortcut if known
        if let key = command.shortcutKey, let modifiers = command.shortcutModifiers {
            if synthesizeShortcut(key: key, axModifiers: modifiers) {
                return .success
            }
        }

        return .failed("Couldn't run command")
    }

    private static func runExtension(named name: String) -> Result {
        guard let url = ExtensionLoader.scriptURL(named: name) else {
            return .failed("Extension not found")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [url.path]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? .success : .failed("Extension failed")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func synthesizeShortcut(key: String, axModifiers: Int) -> Bool {
        guard let first = key.uppercased().unicodeScalars.first else { return false }
        let keyCode = keyCodeForCharacter(Character(first))
        guard keyCode != 0xFFFF else { return false }

        var cgFlags: CGEventFlags = []
        // AX: bit0=cmd implied often, bit1=shift, bit2=option, bit3=control
        if axModifiers & (1 << 0) != 0 || axModifiers == 0 { cgFlags.insert(.maskCommand) }
        if axModifiers & (1 << 1) != 0 { cgFlags.insert(.maskShift) }
        if axModifiers & (1 << 2) != 0 { cgFlags.insert(.maskAlternate) }
        if axModifiers & (1 << 3) != 0 { cgFlags.insert(.maskControl) }

        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }
        down.flags = cgFlags
        up.flags = cgFlags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private static func keyCodeForCharacter(_ ch: Character) -> CGKeyCode {
        let map: [Character: CGKeyCode] = [
            "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8, "V": 9,
            "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15, "Y": 16, "T": 17, "1": 18, "2": 19,
            "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
            "0": 29, "]": 30, "O": 31, "U": 32, "[": 33, "I": 34, "P": 35, "L": 37, "J": 38,
            "'": 39, "K": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "N": 45, "M": 46, ".": 47,
            "`": 50
        ]
        return map[ch] ?? 0xFFFF
    }
}
