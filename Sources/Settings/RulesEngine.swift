import Foundation

struct ExcludeRule: Codable, Identifiable, Hashable {
    var id: UUID
    var titleExact: String?
    var pathPrefix: String?
    var regex: String?
    var bundleID: String?

    init(
        id: UUID = UUID(),
        titleExact: String? = nil,
        pathPrefix: String? = nil,
        regex: String? = nil,
        bundleID: String? = nil
    ) {
        self.id = id
        self.titleExact = titleExact
        self.pathPrefix = pathPrefix
        self.regex = regex
        self.bundleID = bundleID
    }

    /// Returns true when this rule says the command should be excluded.
    func matches(_ command: MenuCommand, bundleID: String?) -> Bool {
        if let ruleBundle = self.bundleID, !ruleBundle.isEmpty, ruleBundle != bundleID {
            return false
        }

        var anyCriterion = false
        var allMatched = true

        if let titleExact, !titleExact.isEmpty {
            anyCriterion = true
            if command.title.caseInsensitiveCompare(titleExact) != .orderedSame {
                allMatched = false
            }
        }

        if let pathPrefix, !pathPrefix.isEmpty {
            anyCriterion = true
            let breadcrumb = command.path.joined(separator: " → ")
            let slash = command.path.joined(separator: "/")
            let hit = breadcrumb.localizedCaseInsensitiveContains(pathPrefix)
                || slash.localizedCaseInsensitiveContains(pathPrefix)
            if !hit { allMatched = false }
        }

        if let regex, !regex.isEmpty {
            anyCriterion = true
            let text = command.breadcrumb + " " + command.title
            if let expression = try? NSRegularExpression(pattern: regex, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..., in: text)
                if expression.firstMatch(in: text, options: [], range: range) == nil {
                    allMatched = false
                }
            } else {
                allMatched = false
            }
        }

        return anyCriterion && allMatched
    }
}

final class RulesEngine {
    var disabledBundleIDs: Set<String>
    var excludeRules: [ExcludeRule]

    init(disabledBundleIDs: Set<String> = [], excludeRules: [ExcludeRule] = []) {
        self.disabledBundleIDs = disabledBundleIDs
        self.excludeRules = excludeRules
    }

    func isAppEnabled(bundleID: String?) -> Bool {
        guard let bundleID else { return true }
        return !disabledBundleIDs.contains(bundleID)
    }

    func shouldInclude(_ command: MenuCommand, bundleID: String?) -> Bool {
        !excludeRules.contains { $0.matches(command, bundleID: bundleID) }
    }
}
