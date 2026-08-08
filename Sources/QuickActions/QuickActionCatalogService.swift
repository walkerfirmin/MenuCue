import Foundation

final class QuickActionCatalogService {
    static let shared = QuickActionCatalogService()

    private let store: QuickActionCatalogStore
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(store: QuickActionCatalogStore = .shared, session: URLSession = .shared) {
        self.store = store
        self.session = session
    }

    struct LoadResult {
        var entries: [CatalogEntry]
        var sources: [RepoSource]
        var warnings: [String]
    }

    func loadMergedCatalog() async -> LoadResult {
        var warnings: [String] = []
        var sources: [RepoSource] = []
        var collected: [CatalogEntry] = []

        // Remote official
        let defaultURL = store.defaultIndexURL
        do {
            let (index, base) = try await fetchIndex(from: defaultURL)
            let source = RepoSource(
                name: index.name,
                urlString: defaultURL.absoluteString,
                isDefault: true,
                isBundledFallback: false
            )
            sources.append(source)
            collected.append(contentsOf: entries(from: index, source: source, baseURL: base))
        } catch {
            warnings.append("Official remote index unavailable (\(error.localizedDescription)); using bundled catalog.")
            if let bundled = loadBundledIndex() {
                let (index, base) = bundled
                let source = RepoSource(
                    name: "\(index.name) (Bundled)",
                    urlString: base.appendingPathComponent("index.json").absoluteString,
                    isDefault: true,
                    isBundledFallback: true
                )
                sources.append(source)
                collected.append(contentsOf: entries(from: index, source: source, baseURL: base))
            } else {
                warnings.append("Bundled catalog is missing from the app bundle.")
            }
        }

        // User indexes
        let userURLs = store.userIndexURLs
        for url in userURLs {
            do {
                let (index, base) = try await fetchIndex(from: url)
                let source = RepoSource(
                    name: index.name,
                    urlString: url.absoluteString,
                    isDefault: false,
                    isBundledFallback: false
                )
                sources.append(source)
                collected.append(contentsOf: entries(from: index, source: source, baseURL: base))
            } catch {
                warnings.append("Failed to load \(url.absoluteString): \(error.localizedDescription)")
            }
        }

        let merged = mergeByPackageID(collected)
        return LoadResult(entries: merged, sources: sources, warnings: warnings)
    }

    func loadPackageDetail(entry: CatalogEntry) async throws -> (package: QuickActionPackage, readme: String) {
        let packageURL = entry.baseURL.appendingPathComponent(entry.summary.path).appendingPathComponent("package.json")
        let packageData = try await loadData(from: packageURL)
        let package: QuickActionPackage
        do {
            package = try decoder.decode(QuickActionPackage.self, from: packageData)
        } catch {
            throw QuickActionCatalogError.decodeFailed(packageURL.absoluteString)
            
        }

        let readmeName = package.readme.isEmpty ? "README.md" : package.readme
        let readmeURL = entry.baseURL.appendingPathComponent(entry.summary.path).appendingPathComponent(readmeName)
        let readme: String
        if let data = try? await loadData(from: readmeURL), let text = String(data: data, encoding: .utf8) {
            readme = text
        } else {
            readme = "_No README available._"
        }
        return (package, readme)
    }

    func resolveWorkflowZipURL(entry: CatalogEntry, package: QuickActionPackage) -> URL {
        entry.baseURL
            .appendingPathComponent(entry.summary.path)
            .appendingPathComponent(package.workflowZip)
    }

    // MARK: - Private

    private func entries(from index: CatalogIndex, source: RepoSource, baseURL: URL) -> [CatalogEntry] {
        index.packages.map { CatalogEntry(summary: $0, source: source, baseURL: baseURL) }
    }

    /// Keep highest semver per package id; prefer non-bundled when versions equal.
    private func mergeByPackageID(_ entries: [CatalogEntry]) -> [CatalogEntry] {
        var best: [String: CatalogEntry] = [:]
        for entry in entries {
            let id = entry.summary.id
            guard let existing = best[id] else {
                best[id] = entry
                continue
            }
            let cmp = compareSemver(entry.summary.version, existing.summary.version)
            if cmp > 0 {
                best[id] = entry
            } else if cmp == 0 {
                if existing.source.isBundledFallback && !entry.source.isBundledFallback {
                    best[id] = entry
                }
            }
        }
        return best.values.sorted {
            $0.summary.name.localizedCaseInsensitiveCompare($1.summary.name) == .orderedAscending
        }
    }

    private func fetchIndex(from url: URL) async throws -> (CatalogIndex, URL) {
        guard let scheme = url.scheme?.lowercased() else {
            throw QuickActionCatalogError.invalidURL(url.absoluteString)
        }
        if scheme == "https" {
            let data = try await loadData(from: url)
            let index = try decodeIndex(data, label: url.absoluteString)
            let base = url.deletingLastPathComponent()
            return (index, base)
        }
        if scheme == "file" {
            let data = try Data(contentsOf: url)
            let index = try decodeIndex(data, label: url.path)
            return (index, url.deletingLastPathComponent())
        }
        throw QuickActionCatalogError.httpsRequired(url.absoluteString)
    }

    private func decodeIndex(_ data: Data, label: String) throws -> CatalogIndex {
        do {
            return try decoder.decode(CatalogIndex.self, from: data)
        } catch {
            throw QuickActionCatalogError.decodeFailed(label)
        }
    }

    private func loadData(from url: URL) async throws -> Data {
        if url.isFileURL {
            do {
                return try Data(contentsOf: url)
            } catch {
                throw QuickActionCatalogError.fetchFailed(url.path, error)
            }
        }
        guard url.scheme?.lowercased() == "https" else {
            throw QuickActionCatalogError.httpsRequired(url.absoluteString)
        }
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw QuickActionCatalogError.fetchFailed(
                    url.absoluteString,
                    NSError(domain: "HTTP", code: http.statusCode, userInfo: [
                        NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"
                    ])
                )
            }
            return data
        } catch let error as QuickActionCatalogError {
            throw error
        } catch {
            throw QuickActionCatalogError.fetchFailed(url.absoluteString, error)
        }
    }

    private func loadBundledIndex() -> (CatalogIndex, URL)? {
        guard let url = Bundle.main.url(
            forResource: "index",
            withExtension: "json",
            subdirectory: "QuickActionsCatalog"
        ) ?? Bundle.main.url(forResource: "index", withExtension: "json", subdirectory: nil) else {
            // Try folder reference style
            if let resourceURL = Bundle.main.resourceURL?
                .appendingPathComponent("QuickActionsCatalog")
                .appendingPathComponent("index.json"),
               FileManager.default.fileExists(atPath: resourceURL.path),
               let data = try? Data(contentsOf: resourceURL),
               let index = try? decoder.decode(CatalogIndex.self, from: data) {
                return (index, resourceURL.deletingLastPathComponent())
            }
            return nil
        }
        guard let data = try? Data(contentsOf: url),
              let index = try? decoder.decode(CatalogIndex.self, from: data) else {
            return nil
        }
        return (index, url.deletingLastPathComponent())
    }

    /// Returns -1, 0, 1 for a < b, equal, a > b. Non-numeric parts compare lexicographically.
    private func compareSemver(_ a: String, _ b: String) -> Int {
        let ap = a.split(separator: ".").map(String.init)
        let bp = b.split(separator: ".").map(String.init)
        let n = max(ap.count, bp.count)
        for i in 0..<n {
            let av = i < ap.count ? ap[i] : "0"
            let bv = i < bp.count ? bp[i] : "0"
            if let ai = Int(av), let bi = Int(bv) {
                if ai != bi { return ai < bi ? -1 : 1 }
            } else if av != bv {
                return av < bv ? -1 : 1
            }
        }
        return 0
    }
}

enum QuickActionPackageRanker {
    static func filter(_ entries: [CatalogEntry], query: String) -> [CatalogEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return entries }

        return entries
            .compactMap { entry -> (CatalogEntry, Int)? in
                let name = entry.summary.name.lowercased()
                let summary = entry.summary.summary.lowercased()
                let tags = entry.summary.tags.map { $0.lowercased() }.joined(separator: " ")
                let hay = "\(name) \(summary) \(tags)"
                guard hay.contains(trimmed) || fuzzyMatch(needle: trimmed, haystack: name) else {
                    return nil
                }
                var score = 0
                if name.hasPrefix(trimmed) { score += 100 }
                if name.contains(trimmed) { score += 50 }
                if tags.contains(trimmed) { score += 30 }
                if summary.contains(trimmed) { score += 10 }
                score += fuzzyScore(needle: trimmed, haystack: name)
                return (entry, score)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private static func fuzzyMatch(needle: String, haystack: String) -> Bool {
        var ni = needle.startIndex
        var hi = haystack.startIndex
        while ni < needle.endIndex && hi < haystack.endIndex {
            if needle[ni] == haystack[hi] {
                ni = needle.index(after: ni)
            }
            hi = haystack.index(after: hi)
        }
        return ni == needle.endIndex
    }

    private static func fuzzyScore(needle: String, haystack: String) -> Int {
        guard fuzzyMatch(needle: needle, haystack: haystack) else { return 0 }
        return max(0, 20 - (haystack.count - needle.count))
    }
}
