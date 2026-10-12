import AppKit
import Sparkle

@MainActor
final class UpdateController {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
    )

    var updater: SPUUpdater { controller.updater }

    var automaticUpdatesEnabled: Bool {
        updater.automaticallyChecksForUpdates && updater.automaticallyDownloadsUpdates
    }

    func start() { controller.startUpdater() }

    func checkForUpdates() {
        guard updater.canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }

    func setAutomaticUpdatesEnabled(_ enabled: Bool) {
        // Sparkle permits changing downloads only while automatic checks are enabled.
        if enabled {
            updater.automaticallyChecksForUpdates = true
            updater.automaticallyDownloadsUpdates = true
        } else {
            updater.automaticallyDownloadsUpdates = false
            updater.automaticallyChecksForUpdates = false
        }
    }
}
