import Foundation

enum LaunchAtLoginFormatting {
    static let checkboxTitle = "Launch at login"

    static func message(for error: Error) -> String {
        if let nsError = error as NSError? {
            return nsError.localizedDescription
        }

        return "macOS could not change launch at login."
    }
}
