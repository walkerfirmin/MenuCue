import Foundation
import AppKit
import CryptoKit

enum QuickActionInstaller {
    static var servicesDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Services", isDirectory: true)
    }

    static func isInstalled(workflowFileName: String) -> Bool {
        let url = servicesDirectory.appendingPathComponent(workflowFileName, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func install(
        entry: CatalogEntry,
        package: QuickActionPackage,
        session: URLSession = .shared
    ) async throws {
        let zipURL = QuickActionCatalogService.shared.resolveWorkflowZipURL(entry: entry, package: package)
        let zipData = try await downloadData(from: zipURL, session: session)

        let actual = sha256Hex(zipData)
        let expected = normalizeChecksum(package.checksum)
        guard actual == expected else {
            throw QuickActionCatalogError.checksumMismatch(expected: expected, actual: actual)
        }

        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("MenuCueQA-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let zipFile = tempRoot.appendingPathComponent("workflow.zip")
        try zipData.write(to: zipFile)

        let extractDir = tempRoot.appendingPathComponent("extract", isDirectory: true)
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try unzip(zipFile: zipFile, to: extractDir)

        guard let workflowURL = findWorkflow(in: extractDir, preferredName: package.workflow) else {
            throw QuickActionCatalogError.installFailed("No .workflow bundle found in archive")
        }

        try fm.createDirectory(at: servicesDirectory, withIntermediateDirectories: true)
        let destination = servicesDirectory.appendingPathComponent(workflowURL.lastPathComponent, isDirectory: true)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: workflowURL, to: destination)

        let record = InstalledPackageRecord(
            id: package.id,
            name: package.name,
            version: package.version,
            sourceURL: entry.source.urlString,
            workflowFileName: destination.lastPathComponent,
            installedAt: Date()
        )
        await MainActor.run {
            QuickActionCatalogStore.shared.upsertInstalled(record)
            MenuCache.shared.invalidate()
        }

        // Refresh Services database best-effort
        refreshServicesDatabase()
    }

    @MainActor
    static func installWithDependencies(
        entry: CatalogEntry,
        package: QuickActionPackage
    ) async throws {
        try await install(entry: entry, package: package)
        let formulas = package.dependencies.brew
        if !formulas.isEmpty {
            do {
                try BrewDependencyRunner.runOrCopy(formulas: formulas)
            } catch QuickActionCatalogError.brewNotFound {
                let command = BrewDependencyRunner.installCommand(formulas: formulas)
                let alert = NSAlert()
                alert.messageText = "Homebrew not found"
                alert.informativeText = """
                    The Quick Action was installed, but brew was not found.
                    The install command was copied to the clipboard:

                    \(command)
                    """
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    static func uninstall(packageID: String) throws {
        let store = QuickActionCatalogStore.shared
        guard let record = store.installedRecord(forPackageID: packageID) else {
            throw QuickActionCatalogError.packageNotFound(packageID)
        }
        let destination = servicesDirectory.appendingPathComponent(record.workflowFileName, isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        store.removeInstalled(packageID: packageID)
        MenuCache.shared.invalidate()
        refreshServicesDatabase()
    }

    // MARK: - Helpers

    private static func downloadData(from url: URL, session: URLSession) async throws -> Data {
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

    private static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func normalizeChecksum(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("sha256:") {
            return String(trimmed.dropFirst("sha256:".count))
        }
        return trimmed
    }

    private static func unzip(zipFile: URL, to directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipFile.path, "-d", directory.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw QuickActionCatalogError.installFailed("unzip failed (\(process.terminationStatus))")
        }
    }

    private static func findWorkflow(in directory: URL, preferredName: String) -> URL? {
        let fm = FileManager.default
        let preferred = directory.appendingPathComponent(preferredName, isDirectory: true)
        if fm.fileExists(atPath: preferred.path), !preferred.path.contains("__MACOSX") {
            return preferred
        }
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator {
            if url.pathExtension == "workflow", !url.path.contains("__MACOSX") {
                return url
            }
        }
        return nil
    }

    private static func refreshServicesDatabase() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/pbs")
        process.arguments = ["-flush"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        // Don't wait forever; best-effort
        DispatchQueue.global().async {
            process.waitUntilExit()
        }
    }
}
