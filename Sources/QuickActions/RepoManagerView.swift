import SwiftUI
import AppKit

@MainActor
final class RepoManagerViewModel: ObservableObject {
    @Published var entries: [CatalogEntry] = []
    @Published var sources: [RepoSource] = []
    @Published var warnings: [String] = []
    @Published var query: String = ""
    @Published var selectedSourceFilter: String? = nil // nil = All
    @Published var selectedEntryID: String?
    @Published var detailPackage: QuickActionPackage?
    @Published var detailReadme: String = ""
    @Published var isLoading = false
    @Published var isInstalling = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var showAddRepo = false
    @Published var newRepoURL = ""
    @Published private(set) var installedIDs: Set<String> = []

    private let store = QuickActionCatalogStore.shared

    var filteredEntries: [CatalogEntry] {
        var list = entries
        if let filter = selectedSourceFilter {
            list = list.filter { $0.source.urlString == filter }
        }
        return QuickActionPackageRanker.filter(list, query: query)
    }

    var selectedEntry: CatalogEntry? {
        guard let selectedEntryID else { return nil }
        return entries.first { $0.id == selectedEntryID } ?? filteredEntries.first { $0.id == selectedEntryID }
    }

    func reloadInstalled() {
        installedIDs = Set(store.installedPackages.map(\.id))
    }

    func installedRecord(for entry: CatalogEntry) -> InstalledPackageRecord? {
        store.installedRecord(forPackageID: entry.summary.id)
    }

    func refresh() {
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        reloadInstalled()
        Task {
            let result = await QuickActionCatalogService.shared.loadMergedCatalog()
            self.entries = result.entries
            self.sources = result.sources
            self.warnings = result.warnings
            self.isLoading = false
            self.reloadInstalled()
            if self.selectedEntryID == nil, let first = result.entries.first {
                self.selectedEntryID = first.id
                await self.loadDetail(for: first)
            } else if let selected = self.selectedEntry {
                await self.loadDetail(for: selected)
            }
        }
    }

    func select(_ entry: CatalogEntry) {
        selectedEntryID = entry.id
        Task { await loadDetail(for: entry) }
    }

    func loadDetail(for entry: CatalogEntry) async {
        do {
            let detail = try await QuickActionCatalogService.shared.loadPackageDetail(entry: entry)
            if selectedEntryID == entry.id {
                detailPackage = detail.package
                detailReadme = detail.readme
                errorMessage = nil
            }
        } catch {
            if selectedEntryID == entry.id {
                detailPackage = nil
                detailReadme = ""
                errorMessage = error.localizedDescription
            }
        }
    }

    func addRepository() {
        let trimmed = newRepoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let url = URL(string: trimmed) else {
            errorMessage = QuickActionCatalogError.invalidURL(trimmed).localizedDescription
            return
        }
        do {
            try store.addUserIndexURL(url)
            newRepoURL = ""
            showAddRepo = false
            statusMessage = "Repository added"
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeRepository(_ source: RepoSource) {
        guard !source.isDefault else { return }
        if let url = URL(string: source.urlString) {
            store.removeUserIndexURL(url)
        }
        refresh()
    }

    func installSelected() {
        guard let entry = selectedEntry, let package = detailPackage else { return }
        isInstalling = true
        errorMessage = nil
        statusMessage = nil
        Task {
            do {
                try await QuickActionInstaller.installWithDependencies(entry: entry, package: package)
                reloadInstalled()
                statusMessage = "Installed \(package.name)"
            } catch {
                errorMessage = error.localizedDescription
            }
            isInstalling = false
        }
    }

    func uninstallSelected() {
        guard let entry = selectedEntry else { return }
        do {
            try QuickActionInstaller.uninstall(packageID: entry.summary.id)
            reloadInstalled()
            statusMessage = "Uninstalled \(entry.summary.name)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func needsUpdate(entry: CatalogEntry) -> Bool {
        guard let installed = installedRecord(for: entry) else { return false }
        return installed.version != entry.summary.version
    }
}

struct RepoManagerView: View {
    @StateObject private var model = RepoManagerViewModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                sidebar
                    .frame(minWidth: 240, idealWidth: 280)
                detail
                    .frame(minWidth: 360)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let status = model.statusMessage {
                Divider()
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
        .frame(
            minWidth: 600,
            idealWidth: 960,
            maxWidth: .infinity,
            minHeight: 420,
            idealHeight: 600,
            maxHeight: .infinity,
            alignment: .top
        )
        .onAppear { model.refresh() }
        .sheet(isPresented: $model.showAddRepo) {
            addRepoSheet
        }
        .alert("Error", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            TextField("Search Quick Actions", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)

            Picker("Source", selection: $model.selectedSourceFilter) {
                Text("All Sources").tag(String?.none)
                ForEach(model.sources) { source in
                    Text(source.name).tag(Optional(source.urlString))
                }
            }
            .frame(maxWidth: 220)

            Spacer()

            Button("Add Repository…") {
                model.showAddRepo = true
            }

            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(model.isLoading)
            .help("Refresh catalogs")
        }
        .padding(12)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.isLoading {
                ProgressView("Loading catalogs…")
                    .padding()
            } else if model.filteredEntries.isEmpty {
                Text("No Quick Actions found")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List(selection: Binding(
                    get: { model.selectedEntryID },
                    set: { id in
                        model.selectedEntryID = id
                        if let id, let entry = model.entries.first(where: { $0.id == id }) {
                            model.select(entry)
                        }
                    }
                )) {
                    ForEach(model.filteredEntries) { entry in
                        packageRow(entry)
                            .tag(entry.id)
                    }
                }
                .listStyle(.sidebar)
            }

            if !model.warnings.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.warnings, id: \.self) { warning in
                        Text(warning)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(8)
            }
        }
    }

    private func packageRow(_ entry: CatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.summary.name)
                    .font(.headline)
                Spacer()
                if model.installedIDs.contains(entry.summary.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .help("Installed")
                }
            }
            Text(entry.summary.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(entry.summary.version)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(entry.source.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var detail: some View {
        Group {
            if let entry = model.selectedEntry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.summary.name)
                                    .font(.title2.bold())
                                Text("v\(entry.summary.version) · \(model.detailPackage?.author ?? entry.source.name)")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            actionButtons(for: entry)
                        }

                        LabeledContent("Source") {
                            Text(entry.source.name)
                        }
                        LabeledContent("URL") {
                            Text(entry.source.urlString)
                                .font(.caption)
                                .textSelection(.enabled)
                        }

                        if let package = model.detailPackage, !package.dependencies.brew.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Homebrew dependencies")
                                    .font(.headline)
                                ForEach(package.dependencies.brew, id: \.self) { formula in
                                    Text("brew install \(formula)")
                                        .font(.system(.body, design: .monospaced))
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        Divider()

                        readmeView
                    }
                    .padding(20)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Select a Quick Action")
                        .font(.headline)
                    Text("Browse the catalog or add a community repository URL.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func actionButtons(for entry: CatalogEntry) -> some View {
        let installed = model.installedRecord(for: entry)
        HStack {
            if installed != nil {
                Button("Uninstall") {
                    model.uninstallSelected()
                }
                .disabled(model.isInstalling)

                if model.needsUpdate(entry: entry) {
                    Button("Update") {
                        model.installSelected()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isInstalling || model.detailPackage == nil)
                }
            } else {
                Button(model.isInstalling ? "Installing…" : "Install") {
                    model.installSelected()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isInstalling || model.detailPackage == nil)
            }
        }
    }

    private var readmeView: some View {
        Group {
            if let attributed = try? AttributedString(
                markdown: model.detailReadme,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) {
                Text(attributed)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(model.detailReadme)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var addRepoSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Repository")
                .font(.title3.bold())
            Text("Paste an HTTPS URL to a Quick Actions `index.json`.")
                .foregroundStyle(.secondary)
            TextField("https://…/index.json", text: $model.newRepoURL)
                .textFieldStyle(.roundedBorder)

            let userSources = model.sources.filter { !$0.isDefault }
            if !userSources.isEmpty {
                Text("Community repositories")
                    .font(.headline)
                ForEach(userSources) { source in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.name)
                            Text(source.urlString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            model.removeRepository(source)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    model.showAddRepo = false
                }
                Button("Add") {
                    model.addRepository()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.newRepoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
