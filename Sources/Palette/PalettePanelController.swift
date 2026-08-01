import AppKit

final class PalettePanelController: NSObject, NSWindowDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var onQueryChange: ((String) -> Void)?
    var onKey: ((PaletteKey) -> Void)?
    var onDismiss: (() -> Void)?
    var onSelectIndex: ((Int) -> Void)?
    var onHoverIndex: ((Int) -> Void)?
    var onOpenAccessibilitySettings: (() -> Void)?

    private var panel: NSPanel?
    private var searchField: NSTextField!
    private var appLabel: NSTextField!
    private var scopeLabel: NSTextField!
    private var diagnosticsLabel: NSTextField!
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var emptyLabel: NSTextField!
    private var emptyDetailLabel: NSTextField!
    private var accessibilityButton: NSButton!
    private var effectView: NSVisualEffectView!

    private var rows: [MenuCommand] = []
    private var selectedIndex = 0
    private var ignoringResign = false
    private var resignWorkItem: DispatchWorkItem?
    private var clickMonitor: Any?
    private var localClickMonitor: Any?

    func show(appName: String, theme: PaletteTheme) {
        MenuCueDebug.log("panel show begin for \(appName)")
        if panel == nil {
            MenuCueDebug.log("panel buildPanel()")
            buildPanel()
            MenuCueDebug.log("panel buildPanel done")
        }
        applyTheme(theme)
        appLabel.stringValue = appName
        scopeLabel.stringValue = ""
        emptyLabel.isHidden = true
        emptyDetailLabel.isHidden = true
        accessibilityButton.isHidden = true
        positionCentered()

        resignWorkItem?.cancel()
        ignoringResign = true
        removeClickOutsideMonitor()

        NSApp.activate(ignoringOtherApps: true)
        panel?.level = .popUpMenu
        panel?.collectionBehavior = [.fullScreenAuxiliary, .transient]
        panel?.orderFrontRegardless()
        panel?.makeKeyAndOrderFront(nil)
        if panel?.makeFirstResponder(searchField) != true {
            searchField.window?.makeFirstResponder(searchField)
        }
        // Force key status for accessory apps on Tahoe.
        if panel?.isKeyWindow != true {
            panel?.becomeKey()
        }
        MenuCueDebug.log("panel ordered front frame=\(NSStringFromRect(panel?.frame ?? .zero)) visible=\(panel?.isVisible ?? false) key=\(panel?.isKeyWindow ?? false)")
        MenuCueLog.palette.info("panel ordered front frame=\(NSStringFromRect(self.panel?.frame ?? .zero), privacy: .public)")

        // Longer settle — Tahoe focus shifts are slower.
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.ignoringResign = false
            NSApp.activate(ignoringOtherApps: true)
            self.panel?.makeKeyAndOrderFront(nil)
            self.panel?.makeFirstResponder(self.searchField)
            self.installClickOutsideMonitor()
            MenuCueDebug.log("panel settle key=\(self.panel?.isKeyWindow ?? false)")
        }
        resignWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func hide() {
        resignWorkItem?.cancel()
        removeClickOutsideMonitor()
        ignoringResign = true
        panel?.orderOut(nil)
        DispatchQueue.main.async { [weak self] in
            self?.ignoringResign = false
        }
    }

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        // Local monitor catches clicks inside our app that miss the panel.
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handlePotentialOutsideClick()
            return event
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.handlePotentialOutsideClick()
        }
    }

    private func handlePotentialOutsideClick() {
        guard let panel, panel.isVisible, !ignoringResign else { return }
        let screenPoint = NSEvent.mouseLocation
        if !panel.frame.contains(screenPoint) {
            onDismiss?()
        }
    }

    private func removeClickOutsideMonitor() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
    }

    func setQuery(_ text: String) {
        searchField?.stringValue = text
    }

    func setResults(
        _ results: [MenuCommand],
        selectedIndex: Int,
        emptyReason: PaletteController.EmptyReason,
        scope: [String],
        diagnostics: String = "",
        emptyDetail: String? = nil
    ) {
        // Don't stash rows before the panel exists — buildPanel clears/uses `rows`
        // during setDataSource and a prefilled list caused selection crashes.
        guard panel != nil else { return }
        rows = results
        self.selectedIndex = selectedIndex
        scopeLabel.stringValue = scope.isEmpty ? "" : scope.joined(separator: " → ")
        diagnosticsLabel.stringValue = diagnostics
        tableView.reloadData()
        if !rows.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
            tableView.scrollRowToVisible(selectedIndex)
        }

        accessibilityButton.isHidden = emptyReason != .needsAccessibility
        emptyDetailLabel.stringValue = emptyDetail ?? ""
        emptyDetailLabel.isHidden = (emptyDetail == nil || emptyDetail?.isEmpty == true)

        switch emptyReason {
        case .none:
            emptyLabel.isHidden = true
            emptyDetailLabel.isHidden = true
            scrollView.isHidden = false
        case .loading:
            emptyLabel.stringValue = "Loading menus…"
            emptyLabel.isHidden = false
            scrollView.isHidden = results.isEmpty
        case .noMenus:
            emptyLabel.stringValue = "No menu items available"
            emptyLabel.isHidden = false
            scrollView.isHidden = true
        case .noResults:
            emptyLabel.stringValue = "No results"
            emptyLabel.isHidden = false
            scrollView.isHidden = true
        case .appDisabled:
            emptyLabel.stringValue = "MenuCue is disabled for this app"
            emptyLabel.isHidden = false
            scrollView.isHidden = true
        case .needsAccessibility:
            emptyLabel.stringValue = "Accessibility permission required"
            emptyLabel.isHidden = false
            scrollView.isHidden = true
        }
    }

    /// Row currently highlighted in the results table (falls back to stored index).
    var highlightedIndex: Int {
        guard panel != nil else { return selectedIndex }
        let row = tableView.selectedRow
        return row >= 0 ? row : selectedIndex
    }

    func updateSelection(_ index: Int) {
        selectedIndex = index
        guard !rows.isEmpty else { return }
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tableView.scrollRowToVisible(index)
    }

    private func buildPanel() {
        // Avoid setDataSource selection callbacks against a pre-filled `rows`
        // (scrape-before-show can stash results before the panel exists).
        rows = []
        selectedIndex = 0

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        // Avoid illegal combinations (e.g. moveToActiveSpace + canJoinAllSpaces aborts on Tahoe).
        panel.collectionBehavior = [.fullScreenAuxiliary, .transient]

        let effect = NSVisualEffectView(frame: panel.contentView!.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        panel.contentView?.addSubview(effect)
        effectView = effect

        let appLabel = NSTextField(labelWithString: "")
        appLabel.font = .systemFont(ofSize: 12, weight: .medium)
        appLabel.textColor = .secondaryLabelColor
        appLabel.translatesAutoresizingMaskIntoConstraints = false

        let scopeLabel = NSTextField(labelWithString: "")
        scopeLabel.font = .systemFont(ofSize: 11, weight: .regular)
        scopeLabel.textColor = .tertiaryLabelColor
        scopeLabel.lineBreakMode = .byTruncatingMiddle
        scopeLabel.translatesAutoresizingMaskIntoConstraints = false

        let search = KeyableSearchField(string: "")
        search.placeholderString = "Search menu commands"
        search.font = .systemFont(ofSize: 18, weight: .regular)
        search.isBordered = false
        search.focusRingType = .none
        search.backgroundColor = .clear
        search.delegate = self
        search.translatesAutoresizingMaskIntoConstraints = false
        search.onSpecialKey = { [weak self] key in
            self?.onKey?(key)
        }

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let table = NSTableView()
        table.headerView = nil
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.rowHeight = 36
        table.allowsEmptySelection = false
        // Assign before delegate/dataSource — setDataSource can post selection
        // notifications that read `tableView` (crash if still nil).
        tableView = table
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.action = #selector(tableClicked)
        table.doubleAction = #selector(tableDoubleClicked)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("cmd"))
        column.width = 520
        table.addTableColumn(column)
        scroll.documentView = table

        let empty = NSTextField(labelWithString: "")
        empty.font = .systemFont(ofSize: 14, weight: .medium)
        empty.textColor = .secondaryLabelColor
        empty.alignment = .center
        empty.translatesAutoresizingMaskIntoConstraints = false
        empty.isHidden = true

        let emptyDetail = NSTextField(labelWithString: "")
        emptyDetail.font = .systemFont(ofSize: 12)
        emptyDetail.textColor = .tertiaryLabelColor
        emptyDetail.alignment = .center
        emptyDetail.maximumNumberOfLines = 3
        emptyDetail.translatesAutoresizingMaskIntoConstraints = false
        emptyDetail.isHidden = true

        let axButton = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openAccessibilitySettings))
        axButton.bezelStyle = .rounded
        axButton.translatesAutoresizingMaskIntoConstraints = false
        axButton.isHidden = true

        let diagnostics = NSTextField(labelWithString: "")
        diagnostics.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        diagnostics.textColor = .tertiaryLabelColor
        diagnostics.lineBreakMode = .byTruncatingTail
        diagnostics.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(appLabel)
        effect.addSubview(scopeLabel)
        effect.addSubview(search)
        effect.addSubview(scroll)
        effect.addSubview(empty)
        effect.addSubview(emptyDetail)
        effect.addSubview(axButton)
        effect.addSubview(diagnostics)

        NSLayoutConstraint.activate([
            appLabel.topAnchor.constraint(equalTo: effect.topAnchor, constant: 14),
            appLabel.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 18),
            appLabel.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -18),

            scopeLabel.topAnchor.constraint(equalTo: appLabel.bottomAnchor, constant: 2),
            scopeLabel.leadingAnchor.constraint(equalTo: appLabel.leadingAnchor),
            scopeLabel.trailingAnchor.constraint(equalTo: appLabel.trailingAnchor),

            search.topAnchor.constraint(equalTo: scopeLabel.bottomAnchor, constant: 8),
            search.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 18),
            search.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -18),
            search.heightAnchor.constraint(equalToConstant: 28),

            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: diagnostics.topAnchor, constant: -6),

            diagnostics.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 18),
            diagnostics.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -18),
            diagnostics.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -10),

            empty.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: effect.centerYAnchor, constant: -10),
            empty.leadingAnchor.constraint(greaterThanOrEqualTo: effect.leadingAnchor, constant: 24),
            empty.trailingAnchor.constraint(lessThanOrEqualTo: effect.trailingAnchor, constant: -24),

            emptyDetail.topAnchor.constraint(equalTo: empty.bottomAnchor, constant: 6),
            emptyDetail.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 32),
            emptyDetail.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -32),

            axButton.topAnchor.constraint(equalTo: emptyDetail.bottomAnchor, constant: 12),
            axButton.centerXAnchor.constraint(equalTo: effect.centerXAnchor)
        ])

        self.panel = panel
        self.searchField = search
        self.appLabel = appLabel
        self.scopeLabel = scopeLabel
        self.diagnosticsLabel = diagnostics
        self.tableView = table
        self.scrollView = scroll
        self.emptyLabel = empty
        self.emptyDetailLabel = emptyDetail
        self.accessibilityButton = axButton
    }

    @objc private func openAccessibilitySettings() {
        onOpenAccessibilitySettings?()
    }

    private func applyTheme(_ theme: PaletteTheme) {
        guard let effectView else { return }
        switch theme {
        case .system:
            effectView.material = .hudWindow
            effectView.appearance = nil
        case .light:
            effectView.material = .sheet
            effectView.appearance = NSAppearance(named: .aqua)
        case .dark:
            effectView.material = .hudWindow
            effectView.appearance = NSAppearance(named: .darkAqua)
        case .graphite:
            effectView.material = .menu
            effectView.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func positionCentered() {
        guard let panel, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.midY - size.height / 2 + 40
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func controlTextDidChange(_ obj: Notification) {
        onQueryChange?(searchField.stringValue)
    }

    /// Field editor receives Return/arrows instead of `NSTextField.keyDown`.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            onKey?(.return)
            return true
        case #selector(NSResponder.moveUp(_:)):
            onKey?(.up)
            return true
        case #selector(NSResponder.moveDown(_:)):
            onKey?(.down)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onKey?(.escape)
            return true
        case #selector(NSResponder.insertTab(_:)),
             #selector(NSResponder.insertBacktab(_:)):
            onKey?(.tab)
            return true
        case #selector(NSResponder.deleteBackward(_:)):
            if searchField.stringValue.isEmpty {
                onKey?(.delete)
                return true
            }
            return false
        default:
            return false
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Do not auto-dismiss on resign-key. Click-outside + Escape handle dismiss.
        // Auto-dismiss here caused flash-close on Tahoe when focus shifted during show.
        if ignoringResign { return }
        DispatchQueue.main.async { [weak self] in
            self?.panel?.makeFirstResponder(self?.searchField)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let command = rows[row]
        let id = NSUserInterfaceItemIdentifier("PaletteRow")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? PaletteRowView) ?? PaletteRowView()
        cell.identifier = id
        cell.configure(command: command)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView else { return }
        let row = table.selectedRow
        guard row >= 0, row < rows.count else { return }
        selectedIndex = row
        onHoverIndex?(row)
    }

    @objc private func tableClicked() {
        let row = tableView.clickedRow
        guard row >= 0 else { return }
        onHoverIndex?(row)
    }

    @objc private func tableDoubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0 else { return }
        onSelectIndex?(row)
    }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class KeyableSearchField: NSTextField {
    var onSpecialKey: ((PaletteKey) -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: onSpecialKey?(.up); return
        case 125: onSpecialKey?(.down); return
        case 36, 76: onSpecialKey?(.return); return
        case 53: onSpecialKey?(.escape); return
        case 48: onSpecialKey?(.tab); return
        case 51: onSpecialKey?(.delete); return
        default: break
        }
        super.keyDown(with: event)
    }
}

final class PaletteRowView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.translatesAutoresizingMaskIntoConstraints = false

        shortcutLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        shortcutLabel.textColor = .secondaryLabelColor
        shortcutLabel.alignment = .right
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(pathLabel)
        addSubview(shortcutLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: shortcutLabel.leadingAnchor, constant: -8),

            pathLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            pathLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 0),
            pathLabel.trailingAnchor.constraint(lessThanOrEqualTo: shortcutLabel.leadingAnchor, constant: -8),
            pathLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),

            shortcutLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcutLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            shortcutLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40)
        ])
    }

    func configure(command: MenuCommand) {
        titleLabel.stringValue = command.isChecked ? "✓ \(command.title)" : command.title
        pathLabel.stringValue = command.breadcrumb
        shortcutLabel.stringValue = command.shortcutDisplay ?? (command.hasSubmenu ? "⇥" : "")
        let alpha: CGFloat = command.isEnabled ? 1.0 : 0.4
        titleLabel.alphaValue = alpha
        pathLabel.alphaValue = alpha
        shortcutLabel.alphaValue = alpha
    }
}
