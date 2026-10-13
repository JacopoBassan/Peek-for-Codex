import Foundation

enum AppMetadata {
    static let fallbackVersion = "0.2.1"

    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? fallbackVersion
    }
}
