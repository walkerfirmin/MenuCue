import Foundation

struct CatalogIndex: Codable, Equatable {
    var schemaVersion: Int
    var name: String
    var updatedAt: String
    var packages: [CatalogPackageSummary]
}

struct CatalogPackageSummary: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var name: String
    var summary: String
    var version: String
    var tags: [String]
    var path: String
}

struct QuickActionPackageDependencies: Codable, Equatable {
    var brew: [String]
}

struct QuickActionPackage: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var version: String
    var author: String
    var readme: String
    var workflow: String
    var workflowZip: String
    var servicesReceives: [String]?
    var dependencies: QuickActionPackageDependencies
    var minMacOS: String?
    var checksum: String
}

struct InstalledPackageRecord: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var version: String
    var sourceURL: String
    var workflowFileName: String
    var installedAt: Date
}

struct RepoSource: Identifiable, Equatable, Hashable {
    var id: String { urlString }
    var name: String
    var urlString: String
    var isDefault: Bool
    var isBundledFallback: Bool
}

/// A package summary resolved against a specific catalog source.
struct CatalogEntry: Identifiable, Hashable {
    var id: String { "\(summary.id)|\(source.urlString)" }
    var summary: CatalogPackageSummary
    var source: RepoSource
    /// Absolute base URL for resolving package paths (directory containing index.json), or file URL for bundled.
    var baseURL: URL
}

enum QuickActionCatalogError: LocalizedError {
    case invalidURL(String)
    case httpsRequired(String)
    case fetchFailed(String, Error)
    case decodeFailed(String)
    case packageNotFound(String)
    case checksumMismatch(expected: String, actual: String)
    case installFailed(String)
    case brewNotFound
    case brewFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let s): return "Invalid URL: \(s)"
        case .httpsRequired(let s): return "Only HTTPS repository URLs are allowed: \(s)"
        case .fetchFailed(let s, let err): return "Failed to fetch \(s): \(err.localizedDescription)"
        case .decodeFailed(let s): return "Failed to decode catalog: \(s)"
        case .packageNotFound(let id): return "Package not found: \(id)"
        case .checksumMismatch(let expected, let actual):
            return "Checksum mismatch (expected \(expected), got \(actual))"
        case .installFailed(let s): return "Install failed: \(s)"
        case .brewNotFound: return "Homebrew (brew) was not found"
        case .brewFailed(let s): return "brew failed: \(s)"
        }
    }
}
