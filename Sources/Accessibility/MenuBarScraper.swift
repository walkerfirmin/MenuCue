import ApplicationServices
import AppKit
import Foundation

final class MenuBarScraper {
    private let settings: SettingsStore
    private let aliasProvider: AliasProvider

    init(settings: SettingsStore = .shared, aliasProvider: AliasProvider = .shared) {
        self.settings = settings
        self.aliasProvider = aliasProvider
    }

    func scrape(pid: pid_t, bundleID: String?, appName: String, cancel: () -> Bool) -> [MenuCommand] {
        let appElement = AXUIElementCreateApplication(pid)
        // Services menus (esp. Chromium) can be large; keep headroom for AX round-trips.
        AXHelper.setTimeout(appElement, seconds: 3.0)

        guard let menuBarRef = AXHelper.copyAttribute(appElement, kAXMenuBarAttribute as String) else {
            NSLog("MenuCue AX: no menu bar for %@ (pid %d, bundle %@)", appName, pid, bundleID ?? "-")
            return []
        }
        let menuBar = menuBarRef as! AXUIElement

        var results: [MenuCommand] = []
        let topMenus = AXHelper.children(menuBar)
        NSLog("MenuCue AX: %@ top menus=%d", appName, topMenus.count)

        for menu in topMenus {
            if cancel() { break }
            let title = AXHelper.stringValue(menu, kAXTitleAttribute as String) ?? ""
            if shouldSkipTopMenu(title) { continue }

            let menuChildren = AXHelper.children(menu)
            for child in menuChildren {
                if cancel() { break }
                let role = AXHelper.role(child) ?? ""
                if role == (kAXMenuRole as String) {
                    walkMenu(child, path: [title], bundleID: bundleID, into: &results, cancel: cancel)
                } else {
                    walkItem(child, path: [title], bundleID: bundleID, into: &results, cancel: cancel)
                }
            }
        }

        let servicesCount = results.filter { command in
            command.path.contains { segment in
                let s = segment.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "…."))
                return s == "services" || s == "dienste" || s == "servicios"
            }
        }.count
        NSLog("MenuCue AX: %@ scraped %d commands (services=%d)", appName, results.count, servicesCount)
        MenuCueDebug.log("scrape \(appName) commands=\(results.count) services=\(servicesCount)")
        return results
    }

    private func shouldSkipTopMenu(_ title: String) -> Bool {
        if title.isEmpty || title == "Apple" || title == "" { return true }
        if settings.filterHelpMenu && (title == "Help" || title == "Hilfe" || title == "Aide") { return true }
        return false
    }

    /// Matches EN/DE Services menu titles (and any path segment under Services).
    private func isServicesTitle(_ title: String, path: [String]) -> Bool {
        let names: Set<String> = ["services", "dienste", "servicios", "services…", "dienste…"]
        let normalized = title.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "…."))
        if names.contains(title.lowercased()) || names.contains(normalized) {
            return true
        }
        return path.contains { segment in
            let s = segment.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "…."))
            return names.contains(segment.lowercased()) || names.contains(s) || s == "services" || s == "dienste"
        }
    }

    private func walkMenu(
        _ menu: AXUIElement,
        path: [String],
        bundleID: String?,
        into results: inout [MenuCommand],
        cancel: () -> Bool
    ) {
        for child in AXHelper.children(menu) {
            if cancel() { return }
            walkItem(child, path: path, bundleID: bundleID, into: &results, cancel: cancel)
        }
    }

    private func walkItem(
        _ element: AXUIElement,
        path: [String],
        bundleID: String?,
        into results: inout [MenuCommand],
        cancel: () -> Bool
    ) {
        let role = AXHelper.role(element) ?? ""
        if role == "AXMenuItemSeparator" || role.contains("Separator") {
            return
        }

        let title = AXHelper.stringValue(element, kAXTitleAttribute as String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if title.isEmpty { return }

        // Optionally skip Services (Automator Quick Actions live here).
        if !settings.includeServicesMenu && isServicesTitle(title, path: path) {
            return
        }

        let enabled = AXHelper.boolValue(element, kAXEnabledAttribute as String) ?? true
        let mark = AXHelper.stringValue(element, kAXMenuItemMarkCharAttribute as String)
        let isChecked = !(mark?.isEmpty ?? true)

        let cmdChar = AXHelper.stringValue(element, kAXMenuItemCmdCharAttribute as String)
        let cmdModifiers = AXHelper.copyAttribute(element, kAXMenuItemCmdModifiersAttribute as String) as? NSNumber
        let modifiers = cmdModifiers?.intValue
        let shortcutDisplay = Self.formatShortcut(char: cmdChar, modifiers: modifiers)

        let children = AXHelper.children(element)
        let submenu = children.first { AXHelper.role($0) == (kAXMenuRole as String) }
        let hasSubmenu = submenu != nil
        let newPath = path + [title]
        let aliases = aliasProvider.aliases(for: title, path: newPath, bundleID: bundleID)
        let id = newPath.joined(separator: "/") + "|" + (shortcutDisplay ?? "")

        let command = MenuCommand(
            id: id,
            title: title,
            path: newPath,
            shortcutDisplay: shortcutDisplay,
            shortcutKey: cmdChar,
            shortcutModifiers: modifiers,
            isEnabled: enabled,
            isChecked: isChecked,
            hasSubmenu: hasSubmenu,
            aliases: aliases,
            element: element,
            isExtension: false,
            extensionScriptName: nil
        )

        if settings.rulesEngine.shouldInclude(command, bundleID: bundleID) {
            if settings.showDisabledItems || enabled {
                results.append(command)
            }
        }

        if let submenu {
            walkMenu(submenu, path: newPath, bundleID: bundleID, into: &results, cancel: cancel)
        }
    }

    static func formatShortcut(char: String?, modifiers: Int?) -> String? {
        guard let char, !char.isEmpty else { return nil }
        let mods = modifiers ?? 0
        // AX modifier bits: 0=cmd, 1=shift, 2=option, 3=ctrl (kAXMenuItemModifier*)
        // When no modifier bits are set, menu items with cmdChar imply Command.
        var parts = ""
        if mods & (1 << 3) != 0 { parts += "⌃" }
        if mods & (1 << 2) != 0 { parts += "⌥" }
        if mods & (1 << 1) != 0 { parts += "⇧" }
        if mods & (1 << 0) != 0 || mods == 0 { parts += "⌘" }
        parts += char.uppercased()
        return parts
    }
}
