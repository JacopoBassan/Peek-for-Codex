import AppKit
import Foundation

enum CodexLocator {
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

        if let bundleURL = workspace.urlForApplication(withBundleIdentifier: "com.openai.codex") {
            return bundleURL
        }

        let candidates = [
            URL(fileURLWithPath: "/Applications/Codex.app"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
                .appendingPathComponent("Codex.app", isDirectory: true),
        ]

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func cliCandidates() -> [URL] {
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }

        let standardPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]

        let searchPaths = Array(NSOrderedSet(array: pathEntries + standardPaths)).compactMap { $0 as? String }
        return searchPaths.map { URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent("codex") }
    }
}
