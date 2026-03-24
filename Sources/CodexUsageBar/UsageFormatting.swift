import Foundation

struct RefreshErrorPresentation {
    let message: String
    let subtitleOverride: String?
}

enum UsageFormatting {
    static func menuBarValue(for window: DisplayWindow) -> String {
        "\(window.remainingPercent)%"
    }

    static func popupValue(for window: DisplayWindow) -> String {
        "\(window.remainingPercent)% remaining"
    }

    static func popupResetString(for window: DisplayWindow) -> String {
        guard let resetDate = window.resetDate else {
            return "Reset time unavailable"
        }

        return "Resets \(resetDate.codexUsageRelativeString()) (\(resetDate.codexUsageAbsoluteString()))"
    }

    static func refreshSubtitle(isRefreshing: Bool, nextRefreshAt: Date?, subtitleOverride: String?) -> String {
        if isRefreshing {
            return "Refreshing..."
        }

        if let subtitleOverride, !subtitleOverride.isEmpty {
            return subtitleOverride
        }

        guard let nextRefreshAt else {
            return "Waiting for first refresh"
        }

        let remaining = max(0, Int(ceil(nextRefreshAt.timeIntervalSinceNow)))
        return "Refresh in \(countdownString(seconds: remaining))"
    }

    static func countdownString(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = seconds / 60
        let secs = seconds % 60

        if hours > 0 {
            let remainingMinutes = (seconds % 3600) / 60
            return "\(hours)h \(remainingMinutes)m"
        }

        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        }

        return "\(secs)s"
    }

    static func refreshErrorPresentation(for error: Error) -> RefreshErrorPresentation {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = message.lowercased()

        if normalized.contains("token_expired")
            || normalized.contains("provided authentication token is expired")
            || normalized.contains("sign in again")
            || normalized.contains("signing in again")
            || (normalized.contains("401") && normalized.contains("unauthorized"))
        {
            return RefreshErrorPresentation(
                message: "Your Codex session expired. Open Codex, sign in again, then refresh.",
                subtitleOverride: "Codex sign-in required"
            )
        }

        return RefreshErrorPresentation(
            message: condensedErrorMessage(message),
            subtitleOverride: nil
        )
    }

    private static func condensedErrorMessage(_ message: String) -> String {
        let condensed = message
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard condensed.count > 220 else {
            return condensed
        }

        let cutoffIndex = condensed.index(condensed.startIndex, offsetBy: 217)
        return "\(condensed[..<cutoffIndex])..."
    }
}
