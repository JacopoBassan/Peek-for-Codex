import Foundation

protocol UsageProviding: Sendable {
    func fetchRateLimits() async throws -> RateLimitSnapshot
    func setNotificationHandler(_ handler: (@Sendable (RateLimitSnapshot) -> Void)?) async
}
