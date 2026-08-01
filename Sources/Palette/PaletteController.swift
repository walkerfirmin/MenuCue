import AppKit
import Combine

@MainActor
final class PaletteController: ObservableObject {
    static let shared = PaletteController()

    @Published private(set) var isVisible = false
    @Published private(set) var isLoading = false
    @Published private(set) var query = ""
    @Published private(set) var targetAppName = ""
    @Published private(set) var results: [MenuCommand] = []
    @Published private(set) var selectedIndex = 0
    @Published private(set) var scopePath: [String] = []
    @Published private(set) var statusMessage: String?
    @Published private(set) var emptyReason: EmptyReason = .none
    @Published private(set) var diagnosticsText = ""

    enum EmptyReason {
        case none
        case loading
        case noMenus
        case noResults
        case appDisabled
        case needsAccessibility
    }

    private let panelController = PalettePanelController()
    private let scraper = MenuBarScraper()
    private let cache = MenuCache.shared
    private let settings = SettingsStore.shared
    private let history = CommandHistory.shared
    private let frontmostTracker = FrontmostAppTracker.shared

    private var targetApp: NSRunningApplication?
    private var allCommands: [MenuCommand] = []
    private var scrapeTask: Task<Void, Never>?
    private let cancelFlag = CancelFlag()
    private var lastScrapeMs: Int = 0

    private init() {
        panelController.onQueryChange = { [weak self] text in
            self?.updateQuery(text)
        }
        panelController.onKey = { [weak self] key in
            self?.handleKey(key)
        }
        panelController.onDismiss = { [weak self] in
            self?.hide()
        }
        panelController.onSelectIndex = { [weak self] index in
            self?.selectedIndex = index
            self?.confirmSelection()
        }
        panelController.onHoverIndex = { [weak self] index in
            self?.selectedIndex = index
            self?.panelController.updateSelection(index)
        }
        panelController.onOpenAccessibilitySettings = {
            AccessibilityPermission.promptIfNeeded()
            AccessibilityPermission.openSystemSettings()
        }
    }

    func start() {
        frontmostTracker.start()
    }

    func toggle() {
        MenuCueLog.palette.info("toggle() isVisible=\(self.isVisible, privacy: .public)")
        if isVisible {
            hide()
            return
        }
        // Don't steal the hotkey experience for apps the user disabled.
        let front = frontmostTracker.resolveTarget()
        if !settings.rulesEngine.isAppEnabled(bundleID: front?.bundleIdentifier) {
            MenuCueDebug.log(
                "hotkey ignored; disabled app \(front?.localizedName ?? "?") (\(front?.bundleIdentifier ?? "-"))"
            )
            MenuCueLog.palette.info(
                "hotkey ignored for disabled app \(front?.bundleIdentifier ?? "-", privacy: .public)"
            )
            return
        }
        show()
    }

    func show() {
        // Snapshot target BEFORE activating ourselves / showing the panel.
        let front = frontmostTracker.resolveTarget()
        let axTrusted = AccessibilityPermission.isTrusted
        MenuCueDebug.log("show() target=\(front?.localizedName ?? "nil") pid=\(front?.processIdentifier ?? -1) ax=\(axTrusted)")
        MenuCueLog.palette.info(
            "show() target=\(front?.localizedName ?? "nil", privacy: .public) pid=\(front?.processIdentifier ?? -1, privacy: .public) ax=\(axTrusted, privacy: .public)"
        )

        if !settings.rulesEngine.isAppEnabled(bundleID: front?.bundleIdentifier) {
            MenuCueDebug.log(
                "show ignored; disabled app \(front?.bundleIdentifier ?? "-")"
            )
            return
        }

        cancelFlag.value = false
        targetApp = front
        targetAppName = front?.localizedName ?? "No application"
        query = ""
        scopePath = []
        selectedIndex = 0
        statusMessage = nil
        isVisible = true
        allCommands = []
        results = []

        if !axTrusted {
            isLoading = false
            emptyReason = .needsAccessibility
            updateDiagnostics(commandCount: 0, note: "AX off")
            let name = targetAppName
            let theme = settings.theme
            let diagnostics = diagnosticsText
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.panelController.show(appName: name, theme: theme)
                self.panelController.setQuery("")
                self.panelController.setResults(
                    [],
                    selectedIndex: 0,
                    emptyReason: .needsAccessibility,
                    scope: [],
                    diagnostics: diagnostics,
                    emptyDetail: "Enable MenuCue in System Settings → Privacy & Security → Accessibility, then press ⌥⌘P again. (⇧⌘P may be taken by another app.)"
                )
                AppDelegate.shared?.closeOnboarding()
                AccessibilityPermission.promptIfNeeded()
            }
            return
        }

        guard let front else {
            isLoading = false
            emptyReason = .noMenus
            updateDiagnostics(commandCount: 0, note: "no target")
            panelController.show(appName: targetAppName, theme: settings.theme)
            panelController.setQuery("")
            panelController.setResults(
                [],
                selectedIndex: 0,
                emptyReason: .noMenus,
                scope: [],
                diagnostics: diagnosticsText,
                emptyDetail: "Couldn’t find an active application to read menus from."
            )
            return
        }

        isLoading = true
        emptyReason = .loading
        updateDiagnostics(commandCount: 0, note: "loading")

        // Chromium-based apps (BrowserOS, Chrome, etc.) only expose the full Services
        // submenu while they remain frontmost. Scrape BEFORE activating our panel.
        scrapeTask?.cancel()
        let bypassCache = settings.includeServicesMenu
        scrapeTask = Task { [weak self] in
            guard let self else { return }
            await self.loadCommands(for: front, bypassCache: bypassCache)
            guard !Task.isCancelled, self.cancelFlag.value == false, self.isVisible else { return }
            await MainActor.run {
                self.presentPanel(
                    emptyReason: self.emptyReason,
                    emptyDetail: nil
                )
            }
        }
    }

    /// Shows the palette after menus are ready (or for error / AX states).
    private func presentPanel(emptyReason: EmptyReason, emptyDetail: String?) {
        let name = targetAppName
        let theme = settings.theme
        let diagnostics = diagnosticsText
        let rows = results
        let selected = selectedIndex
        let scope = scopePath
        MenuCueDebug.log("presentPanel for \(name) rows=\(rows.count) reason=\(emptyReason)")
        // Present off the current Task executor to avoid MainActor reentrancy hangs
        // seen with MenuBarExtra + SwiftUI on Tahoe.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panelController.show(appName: name, theme: theme)
            self.panelController.setQuery(self.query)
            self.panelController.setResults(
                rows,
                selectedIndex: selected,
                emptyReason: emptyReason,
                scope: scope,
                diagnostics: diagnostics,
                emptyDetail: emptyDetail
            )
            MenuCueDebug.log("presentPanel returned for \(name)")
        }
    }

    func hide() {
        cancelFlag.value = true
        scrapeTask?.cancel()
        isVisible = false
        isLoading = false
        panelController.hide()
        targetApp?.activate(options: [.activateIgnoringOtherApps])
    }

    private func loadCommands(for app: NSRunningApplication, bypassCache: Bool) async {
        let pid = app.processIdentifier
        let bundleID = app.bundleIdentifier
        let started = Date()

        if !bypassCache, let cached = cache.get(pid: pid, bundleID: bundleID), !cached.isEmpty {
            let extensions = ExtensionLoader.loadCommands(forBundleID: bundleID)
            let merged = cached + extensions
            await MainActor.run {
                self.lastScrapeMs = 0
                self.allCommands = merged
                self.isLoading = false
                self.emptyReason = merged.isEmpty ? .noMenus : .none
                self.updateDiagnostics(commandCount: merged.count, note: "cache")
                self.refreshResults()
            }
            // Still refresh in background for freshness.
        }

        let flag = cancelFlag
        let scraper = self.scraper
        let scraped: [MenuCommand] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let items = scraper.scrape(
                    pid: pid,
                    bundleID: bundleID,
                    appName: app.localizedName ?? ""
                ) {
                    flag.value
                }
                continuation.resume(returning: items)
            }
        }

        if Task.isCancelled || cancelFlag.value { return }

        let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
        if !scraped.isEmpty {
            cache.set(pid: pid, bundleID: bundleID, commands: scraped)
        } else {
            // Don't poison the cache with empty failures (e.g. brief AX blip).
            cache.invalidateIfMatching(pid: pid, bundleID: bundleID)
        }

        let extensions = ExtensionLoader.loadCommands(forBundleID: bundleID)
        let merged = scraped + extensions

        await MainActor.run {
            self.lastScrapeMs = elapsedMs
            self.allCommands = merged
            self.isLoading = false
            if merged.isEmpty {
                self.emptyReason = AccessibilityPermission.isTrusted ? .noMenus : .needsAccessibility
            } else {
                self.emptyReason = .none
            }
            self.updateDiagnostics(commandCount: merged.count, note: "live")
            self.refreshResults()
            MenuCueDebug.log(
                "scrape done app=\(app.localizedName ?? "?") count=\(merged.count) ms=\(elapsedMs) ax=\(AccessibilityPermission.isTrusted)"
            )
            NSLog(
                "MenuCue scrape: app=%@ pid=%d count=%d ms=%d ax=%d",
                app.localizedName ?? "?",
                pid,
                merged.count,
                elapsedMs,
                AccessibilityPermission.isTrusted
            )
            MenuCueLog.ax.info(
                "scrape done app=\(app.localizedName ?? "?", privacy: .public) count=\(merged.count, privacy: .public) ms=\(elapsedMs, privacy: .public)"
            )
        }
    }

    private func updateDiagnostics(commandCount: Int, note: String) {
        let pid = targetApp.map { String($0.processIdentifier) } ?? "-"
        let ax = AccessibilityPermission.isTrusted ? "AX:on" : "AX:off"
        let ms = lastScrapeMs > 0 ? "\(lastScrapeMs)ms" : note
        diagnosticsText = "\(targetAppName)  pid \(pid)  \(commandCount) cmds  \(ax)  \(ms)"
    }

    private func updateQuery(_ text: String) {
        query = text
        selectedIndex = 0
        refreshResults()
    }

    private func scopedCommands() -> [MenuCommand] {
        guard !scopePath.isEmpty else { return allCommands }
        return allCommands.filter { command in
            command.path.count >= scopePath.count &&
                Array(command.path.prefix(scopePath.count)) == scopePath
        }
    }

    private func refreshResults() {
        let source = scopedCommands()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleID = targetApp?.bundleIdentifier

        if trimmed.isEmpty {
            let recents = history.recents(for: bundleID, limit: settings.historySize)
            var recentCommands: [MenuCommand] = []
            for entry in recents {
                if let match = source.first(where: {
                    $0.title == entry.title && $0.path == entry.path
                }) {
                    recentCommands.append(match)
                }
            }
            let recentIDs = Set(recentCommands.map(\.id))
            let rest = source.filter { !recentIDs.contains($0.id) }
            if scopePath.isEmpty {
                results = recentCommands + Array(rest.prefix(80))
            } else {
                let depth = scopePath.count + 1
                var seen = Set<String>()
                var children: [MenuCommand] = []
                for cmd in source where cmd.path.count >= depth {
                    let key = cmd.path[depth - 1]
                    if seen.insert(key).inserted {
                        if let exact = source.first(where: { $0.path == Array(cmd.path.prefix(depth)) }) {
                            children.append(exact)
                        } else {
                            children.append(cmd)
                        }
                    }
                }
                results = recentCommands.filter { children.contains($0) } + children
            }
        } else {
            results = FuzzyRanker.rank(query: trimmed, commands: source, bundleID: bundleID).map(\.command)
        }

        if isLoading {
            emptyReason = .loading
        } else if emptyReason == .appDisabled || emptyReason == .needsAccessibility {
            // keep
        } else if results.isEmpty {
            emptyReason = trimmed.isEmpty ? .noMenus : .noResults
        } else {
            emptyReason = .none
        }

        if selectedIndex >= results.count {
            selectedIndex = max(0, results.count - 1)
        }

        let detail: String?
        switch emptyReason {
        case .needsAccessibility:
            detail = "Grant Accessibility in System Settings, then press ⇧⌘P again."
        case .noMenus:
            detail = "Couldn’t read menus for \(targetAppName). Check Accessibility, then try again."
        case .noResults:
            detail = "No commands match “\(trimmed)”."
        default:
            detail = nil
        }

        panelController.setResults(
            results,
            selectedIndex: selectedIndex,
            emptyReason: emptyReason,
            scope: scopePath,
            diagnostics: diagnosticsText,
            emptyDetail: detail
        )
    }

    private func handleKey(_ key: PaletteKey) {
        switch key {
        case .up:
            if selectedIndex > 0 {
                selectedIndex -= 1
                panelController.updateSelection(selectedIndex)
            }
        case .down:
            if selectedIndex < results.count - 1 {
                selectedIndex += 1
                panelController.updateSelection(selectedIndex)
            }
        case .return:
            confirmSelection()
        case .escape:
            if !scopePath.isEmpty && query.isEmpty {
                scopePath.removeLast()
                selectedIndex = 0
                refreshResults()
            } else if !query.isEmpty {
                query = ""
                panelController.setQuery("")
                refreshResults()
            } else if !scopePath.isEmpty {
                scopePath.removeLast()
                selectedIndex = 0
                refreshResults()
            } else {
                hide()
            }
        case .tab:
            enterSubmenu()
        case .delete:
            if query.isEmpty && !scopePath.isEmpty {
                scopePath.removeLast()
                selectedIndex = 0
                refreshResults()
            }
        }
    }

    private func enterSubmenu() {
        guard results.indices.contains(selectedIndex) else { return }
        let command = results[selectedIndex]
        let nextPath: [String]
        if command.hasSubmenu {
            nextPath = command.path
        } else if command.path.count > scopePath.count + 1 {
            nextPath = Array(command.path.prefix(scopePath.count + 1))
        } else {
            return
        }
        let deeper = allCommands.contains {
            $0.path.count > nextPath.count && Array($0.path.prefix(nextPath.count)) == nextPath
        }
        guard deeper || command.hasSubmenu else { return }
        scopePath = nextPath
        query = ""
        panelController.setQuery("")
        selectedIndex = 0
        refreshResults()
    }

    private func confirmSelection() {
        guard !results.isEmpty else { return }
        // Prefer the table highlight so Enter matches what the user sees
        // (first row by default, or the row moved to with arrow keys).
        let tableIndex = panelController.highlightedIndex
        let index = results.indices.contains(tableIndex) ? tableIndex : 0
        selectedIndex = index
        let command = results[index]
        guard command.isEnabled else { return }

        if command.hasSubmenu {
            let deeper = allCommands.contains {
                $0.path.count > command.path.count &&
                    Array($0.path.prefix(command.path.count)) == command.path &&
                    $0.id != command.id
            }
            if deeper {
                enterSubmenu()
                return
            }
        }

        guard let target = targetApp else { return }
        hide()
        let result = CommandExecutor.execute(command, target: target)
        switch result {
        case .success:
            history.record(command: command, bundleID: target.bundleIdentifier)
        case .failed(let message):
            statusMessage = message
            NSLog("MenuCue: \(message)")
        }
    }
}

enum PaletteKey {
    case up, down, `return`, escape, tab, delete
}

final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}
