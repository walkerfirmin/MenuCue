import Foundation

final class MenuCache {
    static let shared = MenuCache()

    struct Entry {
        let bundleID: String?
        let pid: pid_t
        let commands: [MenuCommand]
        let fetchedAt: Date
    }

    private var entry: Entry?
    private let lock = NSLock()
    var ttl: TimeInterval = 30

    private init() {}

    func get(pid: pid_t, bundleID: String?) -> [MenuCommand]? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry else { return nil }
        guard entry.pid == pid, entry.bundleID == bundleID else { return nil }
        if Date().timeIntervalSince(entry.fetchedAt) > ttl { return nil }
        return entry.commands
    }

    func set(pid: pid_t, bundleID: String?, commands: [MenuCommand]) {
        lock.lock()
        defer { lock.unlock() }
        entry = Entry(bundleID: bundleID, pid: pid, commands: commands, fetchedAt: Date())
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        entry = nil
    }

    func invalidateIfMatching(pid: pid_t, bundleID: String?) {
        lock.lock()
        defer { lock.unlock() }
        guard let entry, entry.pid == pid, entry.bundleID == bundleID else { return }
        self.entry = nil
    }
}
