import AppKit
import Combine

struct RecentAppInfo: Identifiable, Equatable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
}

/// Continuously tracks the last regular (non-MenuCue) frontmost application
/// so the palette can scrape the correct menus after MenuCue becomes active.
@MainActor
final class FrontmostAppTracker: ObservableObject {
    static let shared = FrontmostAppTracker()

    private(set) var lastRegularApp: NSRunningApplication?
    /// Up to three most recently activated regular apps (newest first).
    @Published private(set) var recentApps: [RecentAppInfo] = []

    private var observer: NSObjectProtocol?
    private let recentLimit = 3

    private init() {}

    func start() {
        guard observer == nil else { return }
        let ownID = Bundle.main.bundleIdentifier

        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != ownID,
           front.activationPolicy == .regular {
            lastRegularApp = front
            recordRecent(front)
        }

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor in
                self?.handleActivation(app)
            }
        }
    }

    private func handleActivation(_ app: NSRunningApplication) {
        let ownID = Bundle.main.bundleIdentifier
        guard app.bundleIdentifier != ownID else { return }
        guard app.activationPolicy == .regular else { return }
        lastRegularApp = app
        recordRecent(app)
    }

    private func recordRecent(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier, !bundleID.isEmpty else { return }
        let info = RecentAppInfo(
            bundleID: bundleID,
            name: app.localizedName ?? bundleID
        )
        var next = recentApps.filter { $0.bundleID != bundleID }
        next.insert(info, at: 0)
        if next.count > recentLimit {
            next = Array(next.prefix(recentLimit))
        }
        recentApps = next
    }

    /// Best target for menu scraping right now.
    func resolveTarget() -> NSRunningApplication? {
        let ownID = Bundle.main.bundleIdentifier
        let front = NSWorkspace.shared.frontmostApplication

        if let front, front.bundleIdentifier != ownID {
            if front.activationPolicy == .regular {
                lastRegularApp = front
                recordRecent(front)
            }
            return front
        }

        if let lastRegularApp, !lastRegularApp.isTerminated, lastRegularApp.bundleIdentifier != ownID {
            return lastRegularApp
        }

        return NSWorkspace.shared.runningApplications.first {
            $0.activationPolicy == .regular &&
            $0.bundleIdentifier != ownID &&
            !$0.isTerminated
        }
    }
}
