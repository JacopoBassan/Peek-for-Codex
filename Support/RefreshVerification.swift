// Exercises refresh through the real reader, model and native menu in a disposable app.
import AppKit

@main
struct RefreshVerification {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "PeekRefreshVerification", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    @MainActor static func main() {
        _ = NSApplication.shared
        Task { @MainActor in
            let client = CodexAppServerClient()
            do {
                let name = CommandLine.arguments[1]
                let output = URL(fileURLWithPath: CommandLine.arguments[2])
                let model = UsageBarModel(client: client,
                    launchAtLoginManager: LaunchAtLoginManager(synchronizesExecutablePath: false))
                let controller = StatusBarController(model: model)
                let members = Mirror(reflecting: controller).children
                (members.first { $0.label == "statusItem" }!.value as! NSStatusItem).isVisible = false
                let menu = members.first { $0.label == "menu" }!.value as! NSMenu
                let refresh = menu.items.first { $0.title == "Refresh" }!
                await model.refresh()
                var rows = [controller.diagnostics()]
                if name == "cold-auth" {
                    try require(model.errorMessage == nil && rows[0][0] == "100%", "Cold authentication recovery failed")
                } else {
                    try require(rows[0][0] == "15%", "Initial quota was not loaded")
                    let updated = model.lastUpdatedAt
                    try require(NSApp.sendAction(refresh.action!, to: refresh.target, from: refresh), "Refresh menu action failed")
                    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
                    while model.lastUpdatedAt == updated && model.errorMessage == nil {
                        try require(ContinuousClock.now < deadline, "Refresh did not finish")
                        try await Task.sleep(for: .milliseconds(20))
                    }
                    while model.isRefreshing { try await Task.sleep(for: .milliseconds(20)) }
                    rows.append(controller.diagnostics())
                    if name == "persistent-auth" || name == "network-failure" {
                        try require(model.errorMessage != nil && model.snapshot == nil && model.lastUpdatedAt == nil,
                            "Failed refresh kept the old snapshot or successful update time")
                        try require(rows[1][0] == "—" && rows[1].contains("Usage unavailable"),
                            "Failed refresh still showed the old percentage as current")
                    } else {
                        try require(model.errorMessage == nil && rows[1][0] == "100%", "Refresh did not recover the current quota")
                    }
                    if name != "persistent-auth" {
                        await model.refresh()
                        rows.append(controller.diagnostics())
                        try require(model.errorMessage == nil && rows.last![0] == "100%", "Later refresh did not recover")
                    }
                }
                await client.shutdown()
                let data = try JSONSerialization.data(withJSONObject: ["status": "passed", "case": name,
                    "nativeRefreshAction": name != "cold-auth", "rows": rows], options: .prettyPrinted)
                try data.write(to: output)
                exit(EXIT_SUCCESS)
            } catch {
                await client.shutdown()
                fputs("Refresh verification failed: \(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }
        RunLoop.main.run()
    }
}
