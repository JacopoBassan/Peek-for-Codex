import AppKit
import Foundation
import SwiftUI

@MainActor
final class UsageBarModel: ObservableObject {
    private enum StorageKey {
        static let refreshInterval = "refreshIntervalSeconds"
        static let showCreditsInPopup = "showCreditsInPopup"
    }

    @Published private(set) var snapshot: RateLimitSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var nextRefreshAt: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginAvailable = false
    @Published private(set) var launchAtLoginMessage: String?
    @Published private(set) var refreshInterval: RefreshIntervalOption
    @Published private(set) var showsCreditsInPopup: Bool

    private let client: any UsageProviding
    private let launchAtLoginManager: LaunchAtLoginManager
    private let defaults: UserDefaults
    private var refreshTask: Task<Void, Never>?

    init(
        client: any UsageProviding = CodexAppServerClient(),
        launchAtLoginManager: LaunchAtLoginManager = LaunchAtLoginManager(),
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.launchAtLoginManager = launchAtLoginManager
        self.defaults = defaults
        self.refreshInterval = Self.loadRefreshInterval(from: defaults)
        self.showsCreditsInPopup = Self.loadShowsCreditsInPopup(from: defaults)
        syncLaunchAtLoginState()
        Task {
            await client.setNotificationHandler { [weak self] snapshot in
                Task { @MainActor in
                    self?.applySnapshot(snapshot)
                }
            }
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    var displayWindows: [DisplayWindow] {
        snapshot?.displayWindows ?? []
    }

    func start() {
        guard refreshTask == nil else { return }

        startRefreshTask()
    }

    func setRefreshInterval(_ option: RefreshIntervalOption) {
        guard refreshInterval != option else { return }

        refreshInterval = option
        defaults.set(option.rawValue, forKey: StorageKey.refreshInterval)
        nextRefreshAt = Date().addingTimeInterval(option.seconds)

        refreshTask?.cancel()
        refreshTask = nil
        startRefreshTask()
    }

    func setShowsCreditsInPopup(_ isEnabled: Bool) {
        guard showsCreditsInPopup != isEnabled else { return }

        showsCreditsInPopup = isEnabled
        defaults.set(isEnabled, forKey: StorageKey.showCreditsInPopup)
    }

    private func startRefreshTask() {
        refreshTask = Task { [weak self] in
            guard let self else { return }

            await self.refresh()

            while !Task.isCancelled {
                let interval = refreshInterval.seconds
                try? await Task.sleep(for: .seconds(interval))
                await self.refresh()
            }
        }
    }

    func refresh() async {
        isRefreshing = true

        do {
            applySnapshot(try await client.fetchRateLimits())
            nextRefreshAt = Date().addingTimeInterval(refreshInterval.seconds)
        } catch {
            errorMessage = error.localizedDescription
        }

        isRefreshing = false
    }

    func openCodex() {
        if let appURL = CodexLocator.appURL() {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
            return
        }

        guard let codexURL = CodexLocator.cliURL() else {
            return
        }

        let process = Process()
        process.executableURL = codexURL
        process.arguments = ["app"]
        try? process.run()
    }

    func refreshLaunchAtLoginState() {
        syncLaunchAtLoginState()
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        do {
            let state = try launchAtLoginManager.setEnabled(isEnabled)
            applyLaunchAtLoginState(state)
        } catch {
            launchAtLoginMessage = LaunchAtLoginFormatting.message(for: error)
            syncLaunchAtLoginState()
        }
    }

    private func applySnapshot(_ snapshot: RateLimitSnapshot) {
        self.snapshot = snapshot
        errorMessage = nil
    }

    private func syncLaunchAtLoginState() {
        applyLaunchAtLoginState(launchAtLoginManager.currentState())
    }

    private func applyLaunchAtLoginState(_ state: LaunchAtLoginManager.State) {
        launchAtLoginAvailable = state.isAvailable
        launchAtLoginEnabled = state.isEnabled
        launchAtLoginMessage = state.message
    }

    private static func loadRefreshInterval(from defaults: UserDefaults) -> RefreshIntervalOption {
        let storedValue = defaults.integer(forKey: StorageKey.refreshInterval)
        return RefreshIntervalOption(rawValue: storedValue) ?? .threeMinutes
    }

    private static func loadShowsCreditsInPopup(from defaults: UserDefaults) -> Bool {
        if defaults.object(forKey: StorageKey.showCreditsInPopup) == nil {
            return true
        }

        return defaults.bool(forKey: StorageKey.showCreditsInPopup)
    }
}
