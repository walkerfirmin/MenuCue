import Foundation
import OSLog

enum MenuCueLog {
    static let general = Logger(subsystem: "com.betternowapps.menucue.app", category: "general")
    static let hotkey = Logger(subsystem: "com.betternowapps.menucue.app", category: "hotkey")
    static let palette = Logger(subsystem: "com.betternowapps.menucue.app", category: "palette")
    static let ax = Logger(subsystem: "com.betternowapps.menucue.app", category: "ax")
}
