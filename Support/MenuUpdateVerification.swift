// Runs real native menu actions with a disposable bundle and usage provider.
import AppKit

actor VerificationUsage: UsageProviding {
    func setNotificationHandler(_ handler: (@Sendable (RateLimitSnapshot) -> Void)?) {}
    func fetchRateLimits() -> RateLimitSnapshot {
        RateLimitSnapshot(primary: nil, secondary: nil, credits: nil, planType: nil)
    }
}

@main
struct MenuUpdateVerification {
    static func require(_ condition: Bool, _ message: String) {
        guard condition else { fputs(message + "\n", stderr); exit(EXIT_FAILURE) }
    }
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        UserDefaults.standard.set(Date(), forKey: "SULastCheckTime")
        let updates = UpdateController()
        updates.start()
        let model = UsageBarModel(client: VerificationUsage(),
            launchAtLoginManager: LaunchAtLoginManager(synchronizesExecutablePath: false))
        let controller = StatusBarController(model: model, updates: updates)
        let menu = Mirror(reflecting: controller).children.first { $0.label == "menu" }!.value as! NSMenu
        let toggle = menu.items.first { $0.title == "Automatic Updates" }!
        let check = menu.items.first { $0.title == "Check for Updates…" }!
        require(check.isEnabled && toggle.isEnabled && toggle.state == .on,
            "Initial updater menu state: check=\(check.isEnabled), toggle=\(toggle.isEnabled), state=\(toggle.state.rawValue)")
        require(app.sendAction(toggle.action!, to: toggle.target, from: toggle), "First menu action was not dispatched")
        require(toggle.state == .off && !updates.updater.automaticallyChecksForUpdates
            && !updates.updater.automaticallyDownloadsUpdates, "Automatic updates did not turn off")
        require(app.sendAction(toggle.action!, to: toggle.target, from: toggle), "Second menu action was not dispatched")
        require(toggle.state == .on && updates.updater.automaticallyChecksForUpdates
            && updates.updater.automaticallyDownloadsUpdates, "Automatic updates did not turn on")
        require(app.sendAction(toggle.action!, to: toggle.target, from: toggle), "Third menu action was not dispatched")
        require(!UpdateController().automaticUpdatesEnabled, "Automatic updates preference was not persisted")
        let report: [String: Any] = ["status": "passed", "nativeActionDispatch": true,
            "checkForUpdatesEnabled": check.isEnabled, "automaticUpdatesPersisted": true,
            "rows": controller.diagnostics()]
        let data = try! JSONSerialization.data(withJSONObject: report, options: .prettyPrinted)
        try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        exit(EXIT_SUCCESS)
    }
}
