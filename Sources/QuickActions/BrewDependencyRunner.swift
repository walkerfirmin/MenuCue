import Foundation
import AppKit
import CryptoKit

enum BrewDependencyRunner {
    /// Common Homebrew binary locations.
    static func brewURL() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]
        let fm = FileManager.default
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        // PATH lookup
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["brew"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty,
               fm.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        } catch {
            return nil
        }
        return nil
    }

    static func installCommand(formulas: [String]) -> String {
        let list = formulas.joined(separator: " ")
        return "brew install \(list)"
    }

    /// Shows a confirm alert. Returns `.install` if the user wants brew run,
    /// `.copyOnly` if they only want the command copied, `.cancel` otherwise.
    @MainActor
    static func confirmInstall(formulas: [String]) -> BrewConfirmChoice {
        guard !formulas.isEmpty else { return .skip }
        let command = installCommand(formulas: formulas)
        let alert = NSAlert()
        alert.messageText = "Install Homebrew dependencies?"
        alert.informativeText = """
            This Quick Action needs:

            \(formulas.map { "• \($0)" }.joined(separator: "\n"))

            Command:
            \(command)
            """
        alert.addButton(withTitle: "Install with Homebrew")
        alert.addButton(withTitle: "Copy Command")
        alert.addButton(withTitle: "Skip")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .install
        case .alertSecondButtonReturn:
            return .copyOnly
        default:
            return .skip
        }
    }

    enum BrewConfirmChoice {
        case install
        case copyOnly
        case skip
    }

    @MainActor
    static func runOrCopy(formulas: [String]) throws {
        guard !formulas.isEmpty else { return }
        let command = installCommand(formulas: formulas)
        let choice = confirmInstall(formulas: formulas)
        switch choice {
        case .skip:
            return
        case .copyOnly:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            let alert = NSAlert()
            alert.messageText = "Command copied"
            alert.informativeText = "Paste this in Terminal:\n\n\(command)"
            alert.addButton(withTitle: "OK")
            alert.runModal()
        case .install:
            guard let brew = brewURL() else {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                throw QuickActionCatalogError.brewNotFound
            }
            try runBrewInstall(brewURL: brew, formulas: formulas)
        }
    }

    private static func runBrewInstall(brewURL: URL, formulas: [String]) throws {
        let process = Process()
        process.executableURL = brewURL
        process.arguments = ["install"] + formulas
        let err = Pipe()
        let out = Pipe()
        process.standardError = err
        process.standardOutput = out
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw QuickActionCatalogError.brewFailed(error.localizedDescription)
        }
        guard process.terminationStatus == 0 else {
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: errData, encoding: .utf8) ?? "exit \(process.terminationStatus)"
            throw QuickActionCatalogError.brewFailed(msg)
        }
    }
}
