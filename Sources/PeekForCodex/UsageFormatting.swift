import Foundation

struct RefreshErrorPresentation {
    let message: String
    let subtitleOverride: String?
}

enum UsageFormatting {
    static func resetCountdownString(for resetDate: Date, now: Date = .now) -> String {
        let remaining = resetDate.timeIntervalSince(now)
        guard remaining.isFinite else { return "Reset time unavailable" }
        guard remaining > 0 else { return "Reset pending" }
        guard remaining >= 60 else { return "Resets in less than a minute" }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = remaining >= 86_400 ? [.day, .hour]
            : (remaining >= 3_600 ? [.hour, .minute] : [.minute])
        formatter.unitsStyle = .full
        formatter.zeroFormattingBehavior = .dropAll
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        formatter.calendar = calendar
        guard let duration = formatter.string(from: remaining) else { return "Reset time unavailable" }
        return "Resets in \(duration)"
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
