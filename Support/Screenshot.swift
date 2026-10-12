import AppKit
import Foundation

actor DemoUsage: UsageProviding {
    func setNotificationHandler(_ handler: (@Sendable (RateLimitSnapshot) -> Void)?) {}
    func fetchRateLimits() -> RateLimitSnapshot {
        RateLimitSnapshot(primary: nil,
            secondary: RateLimitWindow(usedPercent: 31, windowDurationMins: 10080,
                resetsAt: Date.now.addingTimeInterval(3 * 86400 + 4 * 3600 + 30).timeIntervalSince1970),
            credits: CreditsSnapshot(balance: "0", hasCredits: false, unlimited: false), planType: "pro")
    }
}

@main
struct MenuScreenshot {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: .darkAqua)
        let screen = NSScreen.main!
        let canvas = NSRect(x: screen.visibleFrame.midX - 170, y: screen.visibleFrame.midY - 215, width: 340, height: 430)
        let backdrop = NSWindow(contentRect: canvas, styleMask: .borderless,
            backing: .buffered, defer: false)
        backdrop.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1)
        backdrop.isReleasedWhenClosed = false
        backdrop.level = .floating
        backdrop.orderFrontRegardless()
        let bar = NSVisualEffectView(frame: NSRect(x: 0, y: canvas.height - 42, width: canvas.width, height: 42))
        bar.material = .headerView
        bar.blendingMode = .withinWindow
        bar.state = .active
        backdrop.contentView!.addSubview(bar)
        let defaults = UserDefaults(suiteName: "me.peek.screenshot.preferences")!
        defaults.setVolatileDomain(["refreshIntervalSeconds": 180, "showCreditsInPopup": true],
            forName: UserDefaults.argumentDomain)
        let model = UsageBarModel(client: DemoUsage(),
            launchAtLoginManager: LaunchAtLoginManager(synchronizesExecutablePath: false), defaults: defaults)
        Task { @MainActor in
            await model.refresh()
            let controller = StatusBarController(model: model)
            let fields = Array(Mirror(reflecting: controller).children)
            let status = fields.first { $0.label == "statusItem" }!.value as! NSStatusItem
            let menu = fields.first { $0.label == "menu" }!.value as! NSMenu
            menu.appearance = NSAppearance(named: .darkAqua)
            _ = controller.diagnostics()
            // Disable demo actions so a screenshot cannot change login settings or open another app.
            for item in menu.items {
                item.target = nil
                item.action = nil
                for child in item.submenu?.items ?? [] { child.target = nil; child.action = nil }
            }
            let output = URL(fileURLWithPath: CommandLine.arguments[1])
            let button = NSButton(frame: .zero)
            button.isBordered = false
            button.image = status.button?.image
            button.attributedTitle = status.button!.attributedTitle
            button.imagePosition = .imageLeft
            button.imageScaling = .scaleNone
            button.contentTintColor = .white
            button.sizeToFit()
            button.setFrameOrigin(NSPoint(x: (bar.bounds.width - button.frame.width) / 2,
                                          y: (bar.bounds.height - button.frame.height) / 2))
            bar.addSubview(button)
            let rect = "\(Int(canvas.minX)),\(Int(screen.frame.maxY - canvas.maxY)),340,430"
            let captureTop = screen.frame.maxY - canvas.maxY
            try! rect.write(to: output.appendingPathComponent("capture-rect.txt"), atomically: true, encoding: .utf8)
            try! JSONSerialization.data(withJSONObject: controller.diagnostics()).write(to: output.appendingPathComponent("screenshot-menu.json"))
            app.activate(ignoringOtherApps: true)
            // Record the actual native menu frame once its tracking window is visible.
            let ready = Timer(timeInterval: 0.25, repeats: false) { _ in
                let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as! [[String: Any]]
                let window = windows.first {
                    ($0[kCGWindowOwnerPID as String] as? Int) == Int(getpid()) &&
                    ($0[kCGWindowLayer as String] as? Int) == NSWindow.Level.popUpMenu.rawValue
                }!
                let bounds = CGRect(dictionaryRepresentation: window[kCGWindowBounds as String] as! CFDictionary)!
                let geometry: [String: Any] = ["menuBounds": [bounds.minX, bounds.minY, bounds.width, bounds.height],
                    "captureBounds": [canvas.minX, captureTop, canvas.width, canvas.height]]
                try! JSONSerialization.data(withJSONObject: geometry).write(to: output.appendingPathComponent("screenshot-layout.json"))
                try! "ready".write(to: output.appendingPathComponent("screenshot-ready"), atomically: true, encoding: .utf8)
            }
            RunLoop.main.add(ready, forMode: .common)
            // Center the native menu under the status control, with the old crop's top and bottom spacing.
            menu.popUp(positioning: menu.items.first,
                       at: NSPoint(x: (canvas.width - menu.size.width) / 2, y: canvas.height - 53),
                       in: backdrop.contentView)
            withExtendedLifetime((controller, backdrop)) {}
            app.terminate(nil)
        }
        app.run()
    }
}
