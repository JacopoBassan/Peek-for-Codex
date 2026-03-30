import Foundation

enum RefreshIntervalOption: Int, CaseIterable, Identifiable {
    case oneMinute = 60
    case threeMinutes = 180
    case fiveMinutes = 300
    case fifteenMinutes = 900

    var id: Int { rawValue }

    var seconds: TimeInterval {
        TimeInterval(rawValue)
    }

    var menuTitle: String {
        switch self {
        case .oneMinute:
            return "Every 1 Minute"
        case .threeMinutes:
            return "Every 3 Minutes"
        case .fiveMinutes:
            return "Every 5 Minutes"
        case .fifteenMinutes:
            return "Every 15 Minutes"
        }
    }
}
