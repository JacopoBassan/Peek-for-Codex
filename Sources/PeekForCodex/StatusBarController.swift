import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let model: UsageBarModel
    private let updates: UpdateController?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var observation: AnyCancellable?
    private var updateObservation: AnyCancellable?
    private let refreshIntervalMenu = NSMenu()
    private let showCreditsItem = NSMenuItem(title: "Show Credits", action: #selector(toggleCredits), keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let checkForUpdatesItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
    private let automaticUpdatesItem = NSMenuItem(title: "Automatic Updates", action: #selector(toggleAutomaticUpdates), keyEquivalent: "")
    private let usageTag = 1000

    init(model: UsageBarModel, updates: UpdateController? = nil) {
        self.model = model
        self.updates = updates
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        addAction("Refresh", action: #selector(refresh), shortcut: "r")
        addAction("Open ChatGPT", action: #selector(openCodex))
        menu.addItem(.separator())
        let timingItem = NSMenuItem(title: "Refresh Timing", action: nil, keyEquivalent: "")
        for option in RefreshIntervalOption.allCases {
            let item = NSMenuItem(title: option.menuTitle, action: #selector(setRefreshInterval(_:)), keyEquivalent: "")
            item.target = self
            item.tag = option.rawValue
            refreshIntervalMenu.addItem(item)
        }
        timingItem.submenu = refreshIntervalMenu
        menu.addItem(timingItem)
        showCreditsItem.target = self
        launchAtLoginItem.target = self
        menu.addItem(showCreditsItem)
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())
        checkForUpdatesItem.target = self
        automaticUpdatesItem.target = self
        menu.addItem(checkForUpdatesItem)
        menu.addItem(automaticUpdatesItem)
        menu.addItem(.separator())
        addAction("Quit Peek", action: #selector(quit), shortcut: "q")
        statusItem.menu = menu
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.image = Self.makeStatusIcon()
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.imageHugsTitle = true
        observation = model.objectWillChange.sink { [weak self] in
            Task { @MainActor in self?.updateLabel() }
        }
        updateObservation = updates?.updater.publisher(for: \.canCheckForUpdates).sink { [weak self] _ in
            Task { @MainActor in self?.syncPreferences() }
        }
        updateLabel()
        syncPreferences()
    }

    private func addAction(_ title: String, action: Selector, shortcut: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: shortcut)
        item.target = self
        menu.addItem(item)
    }

    private func updateLabel() {
        guard let button = statusItem.button else { return }
        let windows = Array(model.displayWindows.prefix(2))
        let title = NSMutableAttributedString(string: " ", attributes: [
            .font: NSFont.systemFont(ofSize: 11.5),
        ])
        for (index, window) in windows.enumerated() {
            if index > 0 { title.append(NSAttributedString(string: "   ·   ")) }
            if !window.isWeeklyWindow {
                title.append(NSAttributedString(string: "\(window.menuBarLabel)   ", attributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]))
            }
            title.append(NSAttributedString(string: "\(window.remainingPercent)%", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ]))
        }
        if windows.isEmpty {
            title.append(NSAttributedString(string: "—", attributes: [
                .font: NSFont.systemFont(ofSize: 11.5),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        button.attributedTitle = title
        let summary = windows.map { "\($0.menuBarLabel): \($0.remainingPercent)% remaining" }.joined(separator: ", ")
        button.toolTip = model.errorMessage ?? (summary.isEmpty
            ? (model.snapshot == nil ? "Loading Codex usage…" : "No current Codex limits") : summary)
        button.setAccessibilityLabel("Peek for Codex")
        button.setAccessibilityValue(button.toolTip)
    }

    private static func makeStatusIcon() -> NSImage {
        // Exact outer contour of OpenAI's Codex vector icon, not a redrawn approximation.
        // Source: Codex app, webview/assets/codex_new-f14177b03534.svg.
        // Codex artwork belongs to OpenAI: https://openai.com/brand/.
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: true) { _ in
            NSColor.black.setFill()
            let silhouette = NSBezierPath()
            silhouette.move(to: NSPoint(x: 9.3316, y: 2.03768))
            silhouette.curve(to: NSPoint(x: 14.356, y: 3.20174),
                             controlPoint1: NSPoint(x: 11.1644, y: 1.54688), controlPoint2: NSPoint(x: 13.0268, y: 2.04668))
            silhouette.curve(to: NSPoint(x: 19.2935, y: 4.70663),
                             controlPoint1: NSPoint(x: 16.0859, y: 2.86512), controlPoint2: NSPoint(x: 17.9511, y: 3.36418))
            silhouette.curve(to: NSPoint(x: 20.7964, y: 9.64217),
                             controlPoint1: NSPoint(x: 20.6356, y: 6.04882), controlPoint2: NSPoint(x: 21.1326, y: 7.91288))
            silhouette.curve(to: NSPoint(x: 21.9625, y: 14.6685),
                             controlPoint1: NSPoint(x: 21.9527, y: 10.9716), controlPoint2: NSPoint(x: 22.4534, y: 12.8349))
            silhouette.curve(to: NSPoint(x: 18.439, y: 18.439),
                             controlPoint1: NSPoint(x: 21.4711, y: 16.5025), controlPoint2: NSPoint(x: 20.1051, y: 17.8657))
            silhouette.curve(to: NSPoint(x: 14.6695, y: 21.9615),
                             controlPoint1: NSPoint(x: 17.8658, y: 20.1047), controlPoint2: NSPoint(x: 16.503, y: 21.47))
            silhouette.curve(to: NSPoint(x: 9.64312, y: 20.7955),
                             controlPoint1: NSPoint(x: 12.8356, y: 22.4528), controlPoint2: NSPoint(x: 10.9727, y: 21.9519))
            silhouette.curve(to: NSPoint(x: 4.70757, y: 19.2926),
                             controlPoint1: NSPoint(x: 7.91371, y: 21.1319), controlPoint2: NSPoint(x: 6.04993, y: 20.635))
            silhouette.curve(to: NSPoint(x: 3.20269, y: 14.357),
                             controlPoint1: NSPoint(x: 3.36558, y: 17.9505), controlPoint2: NSPoint(x: 2.86659, y: 16.0866))
            silhouette.curve(to: NSPoint(x: 2.03863, y: 9.33065),
                             controlPoint1: NSPoint(x: 2.04693, y: 13.0273), controlPoint2: NSPoint(x: 1.54757, y: 11.1638))
            silhouette.curve(to: NSPoint(x: 5.56011, y: 5.55917),
                             controlPoint1: NSPoint(x: 2.52997, y: 7.49759), controlPoint2: NSPoint(x: 3.89436, y: 6.13282))
            silhouette.curve(to: NSPoint(x: 9.3316, y: 2.03768),
                             controlPoint1: NSPoint(x: 6.13382, y: 3.8935), controlPoint2: NSPoint(x: 7.49837, y: 2.52891))
            silhouette.close()
            let scale = AffineTransform(scale: 14.0 / 24.0)
            silhouette.transform(using: scale)
            silhouette.fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        model.refreshLaunchAtLoginState()
        syncPreferences()
        rebuildUsageRows()
    }

    private func syncPreferences() {
        for item in refreshIntervalMenu.items {
            item.state = item.tag == model.refreshInterval.rawValue ? .on : .off
        }
        showCreditsItem.state = model.showsCreditsInPopup ? .on : .off
        launchAtLoginItem.state = model.launchAtLoginEnabled ? .on : .off
        launchAtLoginItem.isEnabled = model.launchAtLoginAvailable
        launchAtLoginItem.toolTip = model.launchAtLoginMessage
        checkForUpdatesItem.isEnabled = updates?.updater.canCheckForUpdates == true
        automaticUpdatesItem.isEnabled = updates != nil
        automaticUpdatesItem.state = updates?.automaticUpdatesEnabled == true ? .on : .off
    }

    private func rebuildUsageRows() {
        menu.items.filter { $0.tag == usageTag }.forEach(menu.removeItem)
        var rows: [NSMenuItem] = []
        func append(_ title: String) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            rows.append(item)
        }
        if let plan = model.snapshot?.planType?.trimmingCharacters(in: .whitespacesAndNewlines), !plan.isEmpty {
            let name = plan.replacingOccurrences(of: "_", with: " ").capitalized
            append("Plan: \(name)")
        }
        if model.showsCreditsInPopup, let credits = model.snapshot?.credits {
            let value = Double(credits.popupDisplayValue).map {
                $0.formatted(.number.precision(.fractionLength(0...2)))
            } ?? credits.popupDisplayValue
            append("Credits: \(value)")
        }
        if !rows.isEmpty { rows.append(.separator()) }
        if model.displayWindows.isEmpty {
            append(model.errorMessage != nil ? "Usage unavailable"
                : (model.snapshot == nil ? "Loading…" : "No current limits"))
        }
        for window in model.displayWindows {
            append("\(window.menuBarLabel) · \(window.remainingPercent)% remaining")
            if let reset = window.resetDate {
                append(UsageFormatting.resetCountdownString(for: reset))
                append("On \(reset.formatted(date: .abbreviated, time: .shortened))")
            }
        }
        if model.errorMessage != nil {
            append(model.refreshSubtitleOverride ?? "Couldn’t refresh")
        } else if let date = model.lastUpdatedAt {
            append("Updated \(date.formatted(date: .omitted, time: .shortened))")
        }
        rows.append(.separator())
        for (index, item) in rows.enumerated() {
            item.tag = usageTag
            menu.insertItem(item, at: index)
        }
    }

    func diagnostics() -> [String] {
        updateLabel()
        syncPreferences()
        rebuildUsageRows()
        let button = statusItem.button
        let icon = button?.image
        let iconDescription = icon?.isTemplate == true && icon?.size == NSSize(width: 14, height: 14)
            ? "Menu-bar icon: Codex cloud (14 pt template)" : "Menu-bar icon unavailable"
        func describe(_ items: [NSMenuItem], prefix: String = "") -> [String] {
            items.flatMap { item -> [String] in
                if item.isSeparatorItem { return [""] }
                let title = item.title.hasPrefix("Credits:") ? "Credits available" : item.title
                let checkmark = item.state == .on ? "✓ " : ""
                let indentation = String(repeating: "  ", count: item.indentationLevel)
                let availability = item.isEnabled || item.action == nil ? "" : " (unavailable)"
                let row = prefix + indentation + checkmark + title + availability
                return [row] + (item.submenu.map { describe($0.items, prefix: "\(item.title): ") } ?? [])
            }
        }
        return [button?.attributedTitle.string.trimmingCharacters(in: .whitespaces) ?? "", iconDescription] + describe(menu.items)
    }

    @objc private func refresh() { Task { await model.refresh() } }
    @objc private func openCodex() { model.openCodex() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func checkForUpdates() { updates?.checkForUpdates() }

    @objc private func toggleAutomaticUpdates() {
        guard let updates else { return }
        updates.setAutomaticUpdatesEnabled(!updates.automaticUpdatesEnabled)
        syncPreferences()
    }

    @objc private func setRefreshInterval(_ sender: NSMenuItem) {
        guard let option = RefreshIntervalOption(rawValue: sender.tag) else { return }
        model.setRefreshInterval(option)
        syncPreferences()
    }

    @objc private func toggleCredits() {
        model.setShowsCreditsInPopup(!model.showsCreditsInPopup)
        syncPreferences()
    }

    @objc private func toggleLaunchAtLogin() {
        model.setLaunchAtLoginEnabled(!model.launchAtLoginEnabled)
        syncPreferences()
    }
}
