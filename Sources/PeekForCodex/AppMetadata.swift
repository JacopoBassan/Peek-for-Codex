import Foundation

enum AppMetadata {
    static let fallbackVersion = "0.1.2"

    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? fallbackVersion
    }
}
