import Foundation

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id: String { "\(bundleID)|\(path.joined(separator: "/"))|\(title)" }
    let bundleID: String
    let path: [String]
    let title: String
    var timestamp: Date
    var count: Int
}

final class CommandHistory {
    static let shared = CommandHistory()

    private let defaultsKey = "commandHistory"
    private let defaults = UserDefaults.standard
    private(set) var entries: [HistoryEntry]

    private init() {
        if let data = defaults.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = decoded
        } else {
            entries = []
        }
    }

    func record(command: MenuCommand, bundleID: String?) {
        let bid = bundleID ?? ""
        if let idx = entries.firstIndex(where: {
            $0.bundleID == bid && $0.title == command.title && $0.path == command.path
        }) {
            entries[idx].timestamp = Date()
            entries[idx].count += 1
            let item = entries.remove(at: idx)
            entries.insert(item, at: 0)
        } else {
            entries.insert(
                HistoryEntry(bundleID: bid, path: command.path, title: command.title, timestamp: Date(), count: 1),
                at: 0
            )
        }
        trim()
        save()
    }

    func recents(for bundleID: String?, limit: Int) -> [HistoryEntry] {
        let filtered: [HistoryEntry]
        if let bundleID {
            filtered = entries.filter { $0.bundleID == bundleID || $0.bundleID.isEmpty }
        } else {
            filtered = entries
        }
        return Array(filtered.prefix(limit))
    }

    func boost(for command: MenuCommand, bundleID: String?) -> Double {
        let bid = bundleID ?? ""
        guard let entry = entries.first(where: {
            $0.bundleID == bid && $0.title == command.title && $0.path == command.path
        }) else { return 0 }
        let ageHours = max(Date().timeIntervalSince(entry.timestamp) / 3600, 0.1)
        return Double(entry.count) / ageHours
    }

    func clear() {
        entries = []
        save()
    }

    private func trim() {
        let max = SettingsStore.shared.historySize
        if entries.count > max {
            entries = Array(entries.prefix(max))
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: defaultsKey)
        }
    }
}
