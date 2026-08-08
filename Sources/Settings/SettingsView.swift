import SwiftUI
import KeyboardShortcuts
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var frontmostTracker = FrontmostAppTracker.shared
    @State private var newBundleID = ""
    @State private var newExcludeKind: ExcludeRuleKind = .titleExact
    @State private var newExcludeValue = ""

    private enum ExcludeRuleKind: String, CaseIterable, Identifiable {
        case titleExact = "Title exact"
        case pathContains = "Path contains"
        var id: String { rawValue }
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            rulesTab
                .tabItem { Label("Rules", systemImage: "line.3.horizontal.decrease.circle") }
            appearanceTab
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            updatesTab
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
        }
        .padding(20)
        .frame(minWidth: 500, minHeight: 480)
    }

    private var generalTab: some View {
        Form {
            Section("Hotkey") {
                KeyboardShortcuts.Recorder("Toggle palette:", name: .togglePalette)
            }
            Section("Accessibility") {
                HStack {
                    Text(AccessibilityPermission.isTrusted ? "Accessibility is enabled" : "Accessibility is not enabled")
                    Spacer()
                    Button("Open System Settings…") {
                        AccessibilityPermission.openSystemSettings()
                    }
                }
            }
            Section("Behavior") {
                Toggle("Show disabled menu items", isOn: $settings.showDisabledItems)
                Toggle("Filter Help menu", isOn: $settings.filterHelpMenu)
                Toggle("Include Services menu", isOn: $settings.includeServicesMenu)
                Text("Automator Quick Actions and other Services")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Manage Quick Action repos…") {
                    RepoManagerController.shared.show()
                }
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
            Section("History") {
                Stepper("Keep \(settings.historySize) recent commands", value: $settings.historySize, in: 5...100)
                Button("Clear History") {
                    CommandHistory.shared.clear()
                }
            }
        }
        .formStyle(.grouped)
    }

    private var rulesTab: some View {
        Form {
            Section("Disabled Apps (bundle IDs)") {
                ForEach(settings.disabledBundleIDs, id: \.self) { id in
                    HStack {
                        Text(id)
                        Spacer()
                        Button(role: .destructive) {
                            settings.removeDisabledBundleID(id)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("com.example.app", text: $newBundleID)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        settings.addDisabledBundleID(newBundleID.trimmingCharacters(in: .whitespaces))
                        newBundleID = ""
                    }
                    .disabled(newBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section("Recent Apps") {
                if frontmostTracker.recentApps.isEmpty {
                    Text("Switch apps to build a short recent list.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(frontmostTracker.recentApps) { app in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name)
                                Text(app.bundleID)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if settings.disabledBundleIDs.contains(app.bundleID) {
                                Text("Disabled")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("Disable") {
                                    settings.addDisabledBundleID(app.bundleID)
                                }
                            }
                        }
                    }
                }
            }
            Section("Exclude Rules") {
                ForEach(settings.excludeRules) { rule in
                    HStack {
                        VStack(alignment: .leading) {
                            if let t = rule.titleExact, !t.isEmpty {
                                Text("Title: \(t)")
                            }
                            if let p = rule.pathPrefix, !p.isEmpty {
                                Text("Path: \(p)")
                            }
                            if let r = rule.regex, !r.isEmpty {
                                Text("Regex: \(r)")
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            settings.excludeRules.removeAll { $0.id == rule.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Picker("", selection: $newExcludeKind) {
                        ForEach(ExcludeRuleKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)

                    TextField(
                        newExcludeKind == .titleExact ? "Exact title" : "Path contains…",
                        text: $newExcludeValue
                    )
                    .textFieldStyle(.roundedBorder)

                    Button("Add") {
                        let trimmed = newExcludeValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        let rule: ExcludeRule
                        switch newExcludeKind {
                        case .titleExact:
                            rule = ExcludeRule(titleExact: trimmed)
                        case .pathContains:
                            rule = ExcludeRule(pathPrefix: trimmed)
                        }
                        settings.excludeRules.append(rule)
                        newExcludeValue = ""
                    }
                    .disabled(newExcludeValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var appearanceTab: some View {
        Form {
            Section("Theme") {
                Picker("Palette theme", selection: $settings.theme) {
                    ForEach(PaletteTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var updatesTab: some View {
        Form {
            Section("Sparkle") {
                Toggle("Check for updates automatically", isOn: $settings.automaticUpdates)
                Button("Check for Updates Now…") {
                    UpdateController.shared?.checkForUpdates()
                }
                Text("Configure SUFeedURL in Info.plist before shipping.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
