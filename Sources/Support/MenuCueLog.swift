import Foundation
import OSLog

enum MenuCueLog {
    static let general = Logger(subsystem: "io.menucue.app", category: "general")
    static let hotkey = Logger(subsystem: "io.menucue.app", category: "hotkey")
    static let palette = Logger(subsystem: "io.menucue.app", category: "palette")
    static let ax = Logger(subsystem: "io.menucue.app", category: "ax")
}
