import Foundation
import AppKit

enum ExtensionLoader {
    static func loadCommands(forBundleID bundleID: String?) -> [MenuCommand] {
        guard let bundleID else { return [] }
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "scpt", subdirectory: "CommandExtensions")
                ?? Bundle.main.urls(forResourcesWithExtension: "scpt", subdirectory: nil) else {
            return []
        }

        var commands: [MenuCommand] = []
        for url in urls {
            let name = url.deletingPathExtension().lastPathComponent
            // Convention: "Finder - Open in Terminal" → applies to Finder
            let parts = name.split(separator: "-", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { continue }
            let appHint = parts[0]
            let title = parts[1]

            if !appMatches(hint: appHint, bundleID: bundleID) { continue }

            commands.append(
                MenuCommand(
                    id: "ext:\(name)",
                    title: title,
                    path: ["Extensions", title],
                    shortcutDisplay: nil,
                    shortcutKey: nil,
                    shortcutModifiers: nil,
                    isEnabled: true,
                    isChecked: false,
                    hasSubmenu: false,
                    aliases: [],
                    element: nil,
                    isExtension: true,
                    extensionScriptName: name
                )
            )
        }
        return commands
    }

    static func scriptURL(named name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: "scpt", subdirectory: "CommandExtensions") {
            return url
        }
        return Bundle.main.url(forResource: name, withExtension: "scpt")
    }

    private static func appMatches(hint: String, bundleID: String) -> Bool {
        let lower = hint.lowercased()
        if bundleID.lowercased().contains(lower) { return true }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           url.deletingPathExtension().lastPathComponent.lowercased() == lower {
            return true
        }
        // Common hints
        let map = [
            "finder": "com.apple.finder",
            "safari": "com.apple.Safari",
            "textedit": "com.apple.TextEdit"
        ]
        if let expected = map[lower], expected == bundleID { return true }
        return false
    }
}
