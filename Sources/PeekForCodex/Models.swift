import Foundation

struct RateLimitSnapshot: Decodable, Sendable {
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let credits: CreditsSnapshot?
    let planType: String?

    enum CodingKeys: String, CodingKey {
        case primary
        case secondary
        case credits
        case planType
        case plan_type
    }

    init(primary: RateLimitWindow?, secondary: RateLimitWindow?, credits: CreditsSnapshot?, planType: String?) {
        self.primary = primary
        self.secondary = secondary
        self.credits = credits
        self.planType = planType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primary = try container.decodeIfPresent(RateLimitWindow.self, forKey: .primary)
        secondary = try container.decodeIfPresent(RateLimitWindow.self, forKey: .secondary)
        credits = try container.decodeIfPresent(CreditsSnapshot.self, forKey: .credits)
        planType = try container.decodeIfPresent(String.self, forKey: .planType)
            ?? container.decodeIfPresent(String.self, forKey: .plan_type)
    }
}

struct RateLimitWindow: Decodable, Sendable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercent
        case used_percent
        case windowDurationMins
        case window_minutes
        case resetsAt
        case resets_at
    }

    init(usedPercent: Double, windowDurationMins: Int?, resetsAt: Double?) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let value = try container.decodeIfPresent(Double.self, forKey: .usedPercent) {
            usedPercent = value
        } else if let value = try container.decodeIfPresent(Double.self, forKey: .used_percent) {
            usedPercent = value
        } else if let value = try container.decodeIfPresent(Int.self, forKey: .usedPercent) {
            usedPercent = Double(value)
        } else if let value = try container.decodeIfPresent(Int.self, forKey: .used_percent) {
            usedPercent = Double(value)
        } else {
            usedPercent = 0
        }

        windowDurationMins = try container.decodeIfPresent(Int.self, forKey: .windowDurationMins)
            ?? container.decodeIfPresent(Int.self, forKey: .window_minutes)

        if let value = try container.decodeIfPresent(Double.self, forKey: .resetsAt) {
            resetsAt = value
        } else if let value = try container.decodeIfPresent(Double.self, forKey: .resets_at) {
            resetsAt = value
        } else if let value = try container.decodeIfPresent(Int.self, forKey: .resetsAt) {
            resetsAt = Double(value)
        } else if let value = try container.decodeIfPresent(Int.self, forKey: .resets_at) {
            resetsAt = Double(value)
        } else {
            resetsAt = nil
        }
    }
}

struct CreditsSnapshot: Decodable, Sendable {
    let balance: String?
    let hasCredits: Bool?
    let unlimited: Bool?

    enum CodingKeys: String, CodingKey {
        case balance
        case hasCredits
        case has_credits
        case unlimited
    }

    init(balance: String?, hasCredits: Bool?, unlimited: Bool?) {
        self.balance = balance
        self.hasCredits = hasCredits
        self.unlimited = unlimited
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        balance = try container.decodeIfPresent(String.self, forKey: .balance)
        hasCredits = try container.decodeIfPresent(Bool.self, forKey: .hasCredits)
            ?? container.decodeIfPresent(Bool.self, forKey: .has_credits)
        unlimited = try container.decodeIfPresent(Bool.self, forKey: .unlimited)
    }
}

extension CreditsSnapshot {
    var popupDisplayValue: String {
        if unlimited == true {
            return "Unlimited"
        }

        if let balance, !balance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return balance
        }

        return "0"
    }
}

struct GetAccountRateLimitsResponse: Decodable, Sendable {
    let rateLimits: RateLimitSnapshot
}

struct LegacyGetAccountRateLimitsResponse: Decodable, Sendable {
    let rate_limits: RateLimitSnapshot
}

struct DisplayWindow: Identifiable, Sendable {
    let id: String
    let label: String
    let usedPercent: Double
    let remainingPercent: Int
    let resetDate: Date?
    let durationMinutes: Int?
}

extension DisplayWindow {
    var isFiveHourWindow: Bool {
        Self.matches(durationMinutes, target: 300, tolerance: 5) || label == "5h"
    }

    var isWeeklyWindow: Bool {
        Self.matches(durationMinutes, target: 10_080, tolerance: 180) || label == "W"
    }

    var menuBarLabel: String {
        switch true {
        case isFiveHourWindow:
            return "5H"
        case isWeeklyWindow:
            return "WK"
        default:
            return label.uppercased()
        }
    }

    var popupLabel: String {
        switch true {
        case isFiveHourWindow:
            return "5 Hours"
        case isWeeklyWindow:
            return "Week"
        default:
            return label.uppercased()
        }
    }

    private static func matches(_ duration: Int?, target: Int, tolerance: Int) -> Bool {
        guard let duration else {
            return false
        }

        return abs(duration - target) <= tolerance
    }
}

extension RateLimitSnapshot {
    var displayWindows: [DisplayWindow] {
        let windows = [primary, secondary].compactMap { $0 }
        return windows
            .map { window in
                let duration = window.windowDurationMins
                let label = Self.label(for: duration)
                let remaining = max(0, min(100, Int((100.0 - window.usedPercent).rounded())))

                return DisplayWindow(
                    id: "\(label)-\(duration ?? -1)",
                    label: label,
                    usedPercent: window.usedPercent,
                    remainingPercent: remaining,
                    resetDate: window.resetsAt.map { Date(timeIntervalSince1970: $0) },
                    durationMinutes: duration
                )
            }
            .sorted { lhs, rhs in
                (lhs.durationMinutes ?? .max) < (rhs.durationMinutes ?? .max)
            }
    }

    var compactSummary: String {
        let preferred = displayWindows.filter { $0.isFiveHourWindow || $0.isWeeklyWindow }
        let windows = preferred.isEmpty ? Array(displayWindows.prefix(2)) : preferred

        guard !windows.isEmpty else {
            return "Codex"
        }

        return windows
            .map { "\($0.label) \($0.remainingPercent)%" }
            .joined(separator: " | ")
    }

    private static func label(for duration: Int?) -> String {
        guard let duration else { return "RL" }

        switch duration {
        case let value where abs(value - 300) <= 5:
            return "5h"
        case let value where abs(value - 10_080) <= 180:
            return "W"
        case let value where abs(value - 60) <= 5:
            return "1h"
        default:
            let roundedDays = Int((Double(duration) / 1_440.0).rounded())
            if roundedDays > 0, abs(duration - (roundedDays * 1_440)) <= 60 {
                return "\(roundedDays)d"
            }

            let roundedHours = Int((Double(duration) / 60.0).rounded())
            if roundedHours > 0, abs(duration - (roundedHours * 60)) <= 5 {
                return "\(roundedHours)h"
            }

            return "\(duration)m"
        }
    }
}

extension Date {
    func codexUsageRelativeString() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: .now)
    }

    func codexUsageAbsoluteString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}
