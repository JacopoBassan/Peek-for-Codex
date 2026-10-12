import AppKit

@main
enum PeekForCodexApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        if CommandLine.arguments.contains("--diagnose-usage") {
            Task { @MainActor in
                let client = CodexAppServerClient()
                let model = UsageBarModel(client: client, launchAtLoginManager: LaunchAtLoginManager(synchronizesExecutablePath: false))
                await model.refresh()
                guard model.errorMessage == nil else {
                    fputs("Usage refresh failed.\n", stderr)
                    await client.shutdown()
                    exit(EXIT_FAILURE)
                }
                let controller = StatusBarController(model: model)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted]
                if let data = try? encoder.encode(controller.diagnostics()) {
                    print(String(decoding: data, as: UTF8.self))
                }
                await client.shutdown()
                exit(EXIT_SUCCESS)
            }
            RunLoop.main.run()
            return
        }
        guard let instance = SingleInstance.acquire() else { return }
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
        withExtendedLifetime(instance) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = UsageBarModel()
    private let updates = UpdateController()
    private var statusController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        updates.start()
        statusController = StatusBarController(model: model, updates: updates)
        model.start()
    }
}
