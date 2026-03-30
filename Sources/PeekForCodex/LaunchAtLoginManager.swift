import AppKit
import Foundation

@MainActor
final class LaunchAtLoginManager {
    private static let fallbackLabel = "me.jacopobassan.peekforcodex"

    struct State {
        let isAvailable: Bool
        let isEnabled: Bool
        let message: String?
    }

    private let fileManager = FileManager.default

    func currentState() -> State {
        guard let executableURL = Bundle.main.executableURL, Bundle.main.bundleURL.pathExtension == "app" else {
            return State(
                isAvailable: false,
                isEnabled: false,
                message: "Available when running the app bundle."
            )
        }

        if !fileManager.isExecutableFile(atPath: executableURL.path) {
            return State(
                isAvailable: false,
                isEnabled: false,
                message: "App executable is unavailable."
            )
        }

        if launchAgentExists {
            try? syncLaunchAgentIfNeeded(executableURL: executableURL)
        }

        return State(
            isAvailable: true,
            isEnabled: launchAgentExists,
            message: launchAgentExists ? nil : "Starts this app at login for your macOS user."
        )
    }

    func setEnabled(_ isEnabled: Bool) throws -> State {
        guard currentState().isAvailable else {
            return currentState()
        }

        if isEnabled {
            try installLaunchAgent()
        } else {
            try removeLaunchAgent()
        }

        return currentState()
    }

    private var label: String {
        Bundle.main.bundleIdentifier ?? Self.fallbackLabel
    }

    private func launchAgentURL(for label: String) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist", isDirectory: false)
    }

    private var launchAgentURL: URL {
        launchAgentURL(for: label)
    }

    private func launchAgentExists(for label: String) -> Bool {
        fileManager.fileExists(atPath: launchAgentURL(for: label).path)
    }

    private var launchAgentExists: Bool {
        launchAgentExists(for: label)
    }

    private func syncLaunchAgentIfNeeded(executableURL: URL) throws {
        guard let configuredExecutablePath = configuredLaunchAgentExecutablePath() else {
            return
        }

        guard configuredExecutablePath != executableURL.path else {
            return
        }

        try writeLaunchAgent(label: label, executableURL: executableURL)
    }

    private func installLaunchAgent() throws {
        guard let executableURL = Bundle.main.executableURL else {
            throw LaunchAtLoginError.bundleUnavailable
        }

        try fileManager.createDirectory(
            at: launchAgentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try writeLaunchAgent(label: label, executableURL: executableURL)
    }

    private func removeLaunchAgent() throws {
        try removeLaunchAgent(label: label)
    }

    private func writeLaunchAgent(label: String, executableURL: URL) throws {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executableURL.path],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
        ]

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: launchAgentURL(for: label), options: .atomic)
    }

    private func configuredLaunchAgentExecutablePath() -> String? {
        guard let data = try? Data(contentsOf: launchAgentURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String],
              let executablePath = arguments.first
        else {
            return nil
        }

        return executablePath
    }

    private func removeLaunchAgent(label: String) throws {
        _ = try? runLaunchctl(arguments: ["bootout", launchDomain, label])

        let url = launchAgentURL(for: label)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private var launchDomain: String {
        "gui/\(getuid())"
    }

    @discardableResult
    private func runLaunchctl(arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let message = error.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LaunchAtLoginError.launchctlFailed(message.isEmpty ? output : message)
        }

        return output
    }
}

private enum LaunchAtLoginError: LocalizedError {
    case bundleUnavailable
    case launchctlFailed(String)

    var errorDescription: String? {
        switch self {
        case .bundleUnavailable:
            return "App bundle is unavailable."
        case .launchctlFailed(let message):
            return message.isEmpty ? "macOS could not update launch at login." : message
        }
    }
}
