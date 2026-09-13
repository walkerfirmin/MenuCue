import Foundation
import Combine
import ServiceManagement

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var showDisabledItems: Bool {
        didSet { defaults.set(showDisabledItems, forKey: Keys.showDisabledItems) }
    }

    @Published var filterHelpMenu: Bool {
        didSet {
            defaults.set(filterHelpMenu, forKey: Keys.filterHelpMenu)
            MenuCache.shared.invalidate()
        }
    }

    @Published var includeServicesMenu: Bool {
        didSet {
            defaults.set(includeServicesMenu, forKey: Keys.includeServicesMenu)
            MenuCache.shared.invalidate()
        }
    }

    @Published var theme: PaletteTheme {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }

    @Published var historySize: Int {
        didSet { defaults.set(historySize, forKey: Keys.historySize) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            updateLoginItem()
        }
    }

    @Published var disabledBundleIDs: [String] {
        didSet {
            defaults.set(disabledBundleIDs, forKey: Keys.disabledBundleIDs)
            rebuildRules()
        }
    }

    @Published var excludeRules: [ExcludeRule] {
        didSet {
            if let data = try? JSONEncoder().encode(excludeRules) {
                defaults.set(data, forKey: Keys.excludeRules)
            }
            rebuildRules()
        }
    }

    @Published var automaticUpdates: Bool {
        didSet {
            defaults.set(automaticUpdates, forKey: Keys.automaticUpdates)
            UpdateController.shared?.setAutomaticChecksEnabled(automaticUpdates)
        }
    }

    private(set) var rulesEngine: RulesEngine
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let showDisabledItems = "showDisabledItems"
        static let filterHelpMenu = "filterHelpMenu"
        static let includeServicesMenu = "includeServicesMenu"
        static let theme = "theme"
        static let historySize = "historySize"
        static let launchAtLogin = "launchAtLogin"
        static let disabledBundleIDs = "disabledBundleIDs"
        static let excludeRules = "excludeRules"
        static let automaticUpdates = "automaticUpdates"
    }

    private init() {
        let showDisabled = defaults.object(forKey: Keys.showDisabledItems) as? Bool ?? false
        let filterHelp = defaults.object(forKey: Keys.filterHelpMenu) as? Bool ?? true
        let includeServices = defaults.object(forKey: Keys.includeServicesMenu) as? Bool ?? true
        let themeRaw = defaults.string(forKey: Keys.theme) ?? PaletteTheme.system.rawValue
        let themeValue = PaletteTheme(rawValue: themeRaw) ?? .system
        let history = defaults.object(forKey: Keys.historySize) as? Int ?? 30
        let login = defaults.bool(forKey: Keys.launchAtLogin)
        let disabled = defaults.stringArray(forKey: Keys.disabledBundleIDs) ?? []
        let autoUpdates = defaults.object(forKey: Keys.automaticUpdates) as? Bool ?? true

        let rules: [ExcludeRule]
        if let data = defaults.data(forKey: Keys.excludeRules),
           let decoded = try? JSONDecoder().decode([ExcludeRule].self, from: data) {
            rules = decoded
        } else {
            rules = [
                ExcludeRule(pathPrefix: "Recent"),
                ExcludeRule(titleExact: "Open Recent")
            ]
        }

        showDisabledItems = showDisabled
        filterHelpMenu = filterHelp
        includeServicesMenu = includeServices
        theme = themeValue
        historySize = history
        launchAtLogin = login
        disabledBundleIDs = disabled
        automaticUpdates = autoUpdates
        excludeRules = rules
        rulesEngine = RulesEngine(
            disabledBundleIDs: Set(disabled),
            excludeRules: rules
        )
    }

    private func rebuildRules() {
        rulesEngine = RulesEngine(
            disabledBundleIDs: Set(disabledBundleIDs),
            excludeRules: excludeRules
        )
    }

    private func updateLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("MenuCue: failed to update login item: \(error)")
        }
    }

    func addDisabledBundleID(_ id: String) {
        guard !id.isEmpty, !disabledBundleIDs.contains(id) else { return }
        disabledBundleIDs.append(id)
    }

    func removeDisabledBundleID(_ id: String) {
        disabledBundleIDs.removeAll { $0 == id }
    }
}

enum PaletteTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case graphite

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .graphite: return "Graphite"
        }
    }
}
