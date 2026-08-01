import Foundation

struct RankedCommand {
    let command: MenuCommand
    let score: Double
}

enum FuzzyRanker {
    static func rank(
        query: String,
        commands: [MenuCommand],
        bundleID: String?,
        history: CommandHistory = .shared
    ) -> [RankedCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return commands.map {
                RankedCommand(command: $0, score: history.boost(for: $0, bundleID: bundleID))
            }
            .sorted { $0.score > $1.score }
        }

        let needle = trimmed.lowercased()
        var ranked: [RankedCommand] = []

        for command in commands {
            guard let score = score(query: needle, command: command, bundleID: bundleID, history: history) else {
                continue
            }
            ranked.append(RankedCommand(command: command, score: score))
        }

        return ranked.sorted { $0.score > $1.score }
    }

    private static func score(
        query: String,
        command: MenuCommand,
        bundleID: String?,
        history: CommandHistory
    ) -> Double? {
        let title = command.title.lowercased()
        let path = command.path.joined(separator: " ").lowercased()
        let aliases = command.aliases.joined(separator: " ").lowercased()
        let shortcut = (command.shortcutDisplay ?? "").lowercased()
        let haystack = "\(title) \(path) \(aliases)"

        var score: Double = 0

        if title == query {
            score += 100
        } else if title.hasPrefix(query) {
            score += 80
        } else if title.contains(query) {
            score += 50
        }

        if path.contains(query) {
            score += 20
        }
        if aliases.contains(query) {
            score += 40
        }
        if !shortcut.isEmpty && (shortcut.contains(query) || query.contains(shortcut.lowercased())) {
            score += 30
        }

        if let fuzzy = fuzzyScore(query: query, in: haystack) {
            score += fuzzy
        } else if score == 0 {
            return nil
        }

        score += history.boost(for: command, bundleID: bundleID) * 5
        // Prefer shorter titles slightly
        score += max(0, 10 - Double(command.title.count) * 0.1)
        return score
    }

    /// Simple subsequence fuzzy score.
    private static func fuzzyScore(query: String, in text: String) -> Double? {
        if query.isEmpty { return 0 }
        var qi = query.startIndex
        var score: Double = 0
        var consecutive: Double = 0
        var lastMatch: String.Index?

        var ti = text.startIndex
        while ti < text.endIndex && qi < query.endIndex {
            if text[ti] == query[qi] {
                consecutive += 1
                score += 1 + consecutive
                if let last = lastMatch, text.distance(from: last, to: ti) == 1 {
                    score += 2
                }
                lastMatch = ti
                qi = query.index(after: qi)
            } else {
                consecutive = 0
            }
            ti = text.index(after: ti)
        }

        guard qi == query.endIndex else { return nil }
        return score
    }
}
