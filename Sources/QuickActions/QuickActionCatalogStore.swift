import Foundation

final class QuickActionCatalogStore {
    static let shared = QuickActionCatalogStore()

    /// Official remote index (raw GitHub). Fetch may fail until published; bundled fallback always works.
    static let defaultIndexURLString =
        "https://raw.githubusercontent.com/walkerfirmin/MenuCue/main/QuickActionsCatalog/index.json"

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum Keys {
        static let userIndexURLs = "quickActionUserIndexURLs"
        static let installedPackages = "quickActionInstalledPackages"
    }

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    var defaultIndexURL: URL {
        URL(string: Self.defaultIndexURLString)!
    }

    var userIndexURLs: [URL] {
        get {
            let strings = defaults.stringArray(forKey: Keys.userIndexURLs) ?? []
            return strings.compactMap { URL(string: $0) }
        }
        set {
            defaults.set(newValue.map(\.absoluteString), forKey: Keys.userIndexURLs)
        }
    }

    func addUserIndexURL(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else {
            throw QuickActionCatalogError.httpsRequired(url.absoluteString)
        }
        var urls = userIndexURLs
        if !urls.contains(url) {
            urls.append(url)
            userIndexURLs = urls
        }
    }

    func removeUserIndexURL(_ url: URL) {
        userIndexURLs = userIndexURLs.filter { $0 != url }
    }

    var installedPackages: [InstalledPackageRecord] {
        get {
            guard let data = defaults.data(forKey: Keys.installedPackages),
                  let decoded = try? decoder.decode([InstalledPackageRecord].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if let data = try? encoder.encode(newValue) {
                defaults.set(data, forKey: Keys.installedPackages)
            }
        }
    }

    func installedRecord(forPackageID id: String) -> InstalledPackageRecord? {
        installedPackages.first { $0.id == id }
    }

    func upsertInstalled(_ record: InstalledPackageRecord) {
        var list = installedPackages.filter { $0.id != record.id }
        list.append(record)
        installedPackages = list
    }

    func removeInstalled(packageID: String) {
        installedPackages = installedPackages.filter { $0.id != packageID }
    }
}
