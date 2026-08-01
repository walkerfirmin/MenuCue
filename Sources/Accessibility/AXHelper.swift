import ApplicationServices
import Foundation

enum AXHelper {
    static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value
    }

    static func stringValue(_ element: AXUIElement, _ attribute: String) -> String? {
        guard let value = copyAttribute(element, attribute) else { return nil }
        return value as? String
    }

    static func boolValue(_ element: AXUIElement, _ attribute: String) -> Bool? {
        guard let value = copyAttribute(element, attribute) else { return nil }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return nil
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        guard let value = copyAttribute(element, kAXChildrenAttribute as String) else { return [] }
        return value as? [AXUIElement] ?? []
    }

    static func role(_ element: AXUIElement) -> String? {
        stringValue(element, kAXRoleAttribute as String)
    }

    static func setTimeout(_ element: AXUIElement, seconds: Float = 1.0) {
        AXUIElementSetMessagingTimeout(element, seconds)
    }
}
