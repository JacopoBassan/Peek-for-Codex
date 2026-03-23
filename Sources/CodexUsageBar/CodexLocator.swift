import AppKit
import Foundation

enum CodexLocator {
    private static let codexBundleIdentifier = "com.openai.codex"

    static func cliURL() -> URL? {
        for candidate in cliCandidates() {
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    static func appURL() -> URL? {
        let workspace = NSWorkspace.shared

        if let bundleURL = workspace.urlForApplication(withBundleIdentifier: codexBundleIdentifier) {
            return bundleURL
        }

        let candidates = [
            URL(fileURLWithPath: "/Applications/Codex.app"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
                .appendingPathComponent("Codex.app", isDirectory: true),
        ]

        return candidates.first(where: isVerifiedCodexApp(at:))
    }

    private static func cliCandidates() -> [URL] {
        var candidates: [URL] = []

        if let appURL = appURL() {
            candidates.append(contentsOf: bundledCLICandidates(in: appURL))
        }

        candidates.append(contentsOf: [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex",
            "/bin/codex",
        ].map(URL.init(fileURLWithPath:)))

        let pathCandidates = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent("codex") }

        candidates.append(contentsOf: pathCandidates)

        var seenPaths = Set<String>()
        return candidates.filter { seenPaths.insert($0.path).inserted }
    }

    private static func bundledCLICandidates(in appURL: URL) -> [URL] {
        [
            appURL.appendingPathComponent("Contents/Resources/codex", isDirectory: false),
            appURL.appendingPathComponent("Contents/MacOS/codex", isDirectory: false),
        ]
    }

    private static func isVerifiedCodexApp(at url: URL) -> Bool {
        Bundle(url: url)?.bundleIdentifier == codexBundleIdentifier
    }
}
