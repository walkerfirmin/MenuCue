import AppKit
import Foundation
import Sparkle

final class UpdateController: NSObject, SPUUpdaterDelegate {
    static var shared: UpdateController?

    private var updaterController: SPUStandardUpdaterController?

    override init() {
        super.init()
        UpdateController.shared = self
    }

    func start() {
        // Skip starting the updater until a real appcast URL is configured.
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        guard let url = URL(string: feed), url.host != nil, url.host != "example.com" else {
            NSLog("MenuCue: Sparkle disabled (configure SUFeedURL for releases)")
            return
        }
        updaterController = SPUStandardUpdaterController(
            startingUpdater: SettingsStore.shared.automaticUpdates,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        guard updaterController != nil else {
            let alert = NSAlert()
            alert.messageText = "Updates not configured"
            alert.informativeText = "Set SUFeedURL and SUPublicEDKey in the project before checking for updates."
            alert.runModal()
            return
        }
        updaterController?.checkForUpdates(nil)
    }
}
