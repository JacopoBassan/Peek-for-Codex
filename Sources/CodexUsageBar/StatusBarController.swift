import AppKit
import SwiftUI

@MainActor
final class StatusBarController {
    private let model: UsageBarModel
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let statusHostingView: NSHostingView<StatusMetersView>
    private let popoverViewController: NativePopoverViewController
    private let contextMenu = NSMenu()
    private let refreshIntervalMenu = NSMenu()
    private let showCreditsItem = NSMenuItem(title: "Show Credits", action: #selector(toggleShowCreditsFromMenu(_:)), keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLoginFromMenu(_:)), keyEquivalent: "")
    private let updatesItem = NSMenuItem(title: "Check for Updates", action: #selector(checkForUpdatesFromMenu), keyEquivalent: "")
    private var refreshIntervalItems: [RefreshIntervalOption: NSMenuItem] = [:]

    init(model: UsageBarModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        popover.behavior = .transient

        statusHostingView = NSHostingView(rootView: StatusMetersView(model: model))
        statusHostingView.frame = NSRect(x: 0, y: 0, width: 1, height: 24)

        popoverViewController = NativePopoverViewController(model: model)
        popover.contentViewController = popoverViewController
        model.refreshLaunchAtLoginState()
        configureContextMenu()

        if let button = statusItem.button {
            button.title = ""
            button.image = nil
            button.addSubview(statusHostingView)
            statusHostingView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                statusHostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 2),
                statusHostingView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                statusHostingView.heightAnchor.constraint(equalToConstant: 22),
            ])

            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        updateStatusItemWidth()
    }

    private func updateStatusItemWidth() {
        let width = statusHostingView.fittingSize.width + 2
        statusItem.length = width
        statusItem.button?.frame.size.width = width
    }

    private func configureContextMenu() {
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "r")
        refreshItem.target = self
        contextMenu.addItem(refreshItem)

        let refreshIntervalItem = NSMenuItem(title: "Refresh Timing", action: nil, keyEquivalent: "")
        configureRefreshIntervalMenu()
        refreshIntervalItem.submenu = refreshIntervalMenu
        contextMenu.addItem(refreshIntervalItem)

        showCreditsItem.target = self
        contextMenu.addItem(showCreditsItem)

        launchAtLoginItem.target = self
        contextMenu.addItem(launchAtLoginItem)

        updatesItem.target = self
        contextMenu.addItem(updatesItem)

        let openItem = NSMenuItem(title: "Open Codex", action: #selector(openCodexFromMenu), keyEquivalent: "")
        openItem.target = self
        contextMenu.addItem(openItem)

        contextMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Peek for Codex", action: #selector(quitFromMenu), keyEquivalent: "q")
        quitItem.target = self
        contextMenu.addItem(quitItem)
    }

    @objc
    private func handleStatusItemClick(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else {
            togglePopover(sender)
            return
        }

        switch event.type {
        case .rightMouseUp:
            syncRefreshIntervalMenuState()
            syncShowCreditsMenuState()
            syncLaunchAtLoginMenuState()
            showContextMenu()
        default:
            togglePopover(sender)
        }
    }

    private func configureRefreshIntervalMenu() {
        refreshIntervalMenu.removeAllItems()
        refreshIntervalItems.removeAll()

        for option in RefreshIntervalOption.allCases {
            let item = NSMenuItem(title: option.menuTitle, action: #selector(setRefreshIntervalFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.tag = option.rawValue
            refreshIntervalMenu.addItem(item)
            refreshIntervalItems[option] = item
        }

        syncRefreshIntervalMenuState()
    }

    private func syncRefreshIntervalMenuState() {
        for option in RefreshIntervalOption.allCases {
            refreshIntervalItems[option]?.state = model.refreshInterval == option ? .on : .off
        }
    }

    private func syncShowCreditsMenuState() {
        showCreditsItem.state = model.showsCreditsInPopup ? .on : .off
    }

    private func syncLaunchAtLoginMenuState() {
        launchAtLoginItem.state = model.launchAtLoginEnabled ? .on : .off
        launchAtLoginItem.isEnabled = model.launchAtLoginAvailable

        if let message = model.launchAtLoginMessage, !message.isEmpty {
            launchAtLoginItem.toolTip = message
        } else {
            launchAtLoginItem.toolTip = nil
        }
    }

    private func showContextMenu() {
        popover.performClose(nil)
        statusItem.menu = contextMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.becomeKey()
        }
    }

    @objc
    private func refreshFromMenu() {
        Task {
            await model.refresh()
        }
    }

    @objc
    private func openCodexFromMenu() {
        model.openCodex()
    }

    @objc
    private func checkForUpdatesFromMenu() {
        guard let url = URL(string: "https://github.com/JacopoBassan/Peek-for-Codex") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    @objc
    private func setRefreshIntervalFromMenu(_ sender: NSMenuItem) {
        guard let option = RefreshIntervalOption(rawValue: sender.tag) else {
            return
        }

        model.setRefreshInterval(option)
        syncRefreshIntervalMenuState()
    }

    @objc
    private func toggleShowCreditsFromMenu(_ sender: NSMenuItem) {
        model.setShowsCreditsInPopup(!model.showsCreditsInPopup)
        syncShowCreditsMenuState()
    }

    @objc
    private func toggleLaunchAtLoginFromMenu(_ sender: NSMenuItem) {
        model.setLaunchAtLoginEnabled(!model.launchAtLoginEnabled)
        syncLaunchAtLoginMenuState()
    }

    @objc
    private func quitFromMenu() {
        NSApp.terminate(nil)
    }
}
