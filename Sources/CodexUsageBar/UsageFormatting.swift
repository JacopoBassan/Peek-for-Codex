import Foundation

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

    static func refreshSubtitle(isRefreshing: Bool, nextRefreshAt: Date?) -> String {
        if isRefreshing {
            return "Refreshing..."
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
}
