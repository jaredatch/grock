import AppKit
import Combine
import Sparkle

/// Owns Sparkle. One instance, started at launch, never under XCTest so the
/// test host does not phone home. Sandbox needs the installer launcher XPC
/// service and its mach-lookup exception (DEC-062).
@MainActor
final class UpdaterController: ObservableObject {
    static let shared = UpdaterController()

    @Published private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController?

    private init() {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// Call once from `applicationDidFinishLaunching`. Sparkle schedules its
    /// background check from here; it only shows UI when an update exists.
    func start() {
        controller?.startUpdater()
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
