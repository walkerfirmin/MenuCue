import Foundation

enum MenuCueDebug {
    private static let path = "/tmp/menucue.log"
    private static let lock = NSLock()

    static func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        NSLog("%@", "MenuCue \(message)")
        lock.lock()
        defer { lock.unlock() }
        let url = URL(fileURLWithPath: path)
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            }
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}
