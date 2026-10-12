import AppKit
import Darwin

/// A process-owned lock also protects launches that occur before AppKit registers the app.
final class SingleInstance {
    private let descriptor: Int32

    private init(descriptor: Int32) { self.descriptor = descriptor }

    deinit { close(descriptor) }

    @MainActor
    static func acquire() -> SingleInstance? {
        let identifier = Bundle.main.bundleIdentifier ?? "me.jacopobassan.peekforcodex"
        let anotherApp = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .contains { $0.processIdentifier != getpid() && $0.isFinishedLaunching && !$0.isTerminated }
        // Older Peek builds did not hold a lock, so also check registered app instances.
        guard !anotherApp else { return nil }
        do {
            let directory = try FileManager.default.url(
                for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            ).appendingPathComponent(identifier, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let path = directory.appendingPathComponent("instance.lock").path
            let descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else { return nil }
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                close(descriptor)
                return nil
            }
            return SingleInstance(descriptor: descriptor)
        } catch {
            fputs("Peek could not create its instance lock.\n", stderr)
            return nil
        }
    }
}
