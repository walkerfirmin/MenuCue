import ApplicationServices
import Foundation

struct MenuCommand: Identifiable, Hashable {
    let id: String
    let title: String
    let path: [String]
    let shortcutDisplay: String?
    let shortcutKey: String?
    let shortcutModifiers: Int?
    let isEnabled: Bool
    let isChecked: Bool
    let hasSubmenu: Bool
    let aliases: [String]
    /// Opaque AX element retained for press; may become stale.
    let element: AXUIElement?
    let isExtension: Bool
    let extensionScriptName: String?

    var breadcrumb: String {
        path.joined(separator: " → ")
    }

    var searchableText: String {
        ([title] + path + aliases).joined(separator: " ")
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MenuCommand, rhs: MenuCommand) -> Bool {
        lhs.id == rhs.id
    }
}
