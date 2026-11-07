import Darwin
import FactoriOSCompat
public import FactoriOSCore
import Foundation
public import UIKit

/// FactoriOS's start-up: SDL owns the app on iOS, so everything happens inside SDL's main callback.
public enum AppEntry {
    /// What the app supplies: the launcher's and the overlay's view controllers.
    private struct Factories {
        let launcher: @MainActor (GameInstallation, LaunchCoordinator) -> UIViewController
        let overlay: @MainActor (any GameInput, GameSettings) -> UIViewController
    }

    /// How long one turn of the launcher's run-loop pump waits for events.
    private static let pumpInterval: TimeInterval = 0.05

    @MainActor private static var factories: Factories?

    /// The SDL3 bundled in the app, which the game's static SDL3 forwards to.
    static var sdlLibrary: URL {
        let frameworks = Bundle.main.privateFrameworksURL ?? Bundle.main.bundleURL.appendingPathComponent("Frameworks")
        return frameworks.appendingPathComponent("SDL3.framework/SDL3")
    }

    /// Loads the bundled SDL3 and hands start-up to SDL_RunApp.
    ///
    /// In SDL's main: the launcher window, then the game. Never returns (the game's static state can't be run twice;
    /// when it ends, the app exits).
    @MainActor
    public static func run(
        launcher: @escaping @MainActor (GameInstallation, LaunchCoordinator) -> UIViewController,
        overlay: @escaping @MainActor (any GameInput, GameSettings) -> UIViewController
    ) -> Never {
        factories = Factories(launcher: launcher, overlay: overlay)
        var error: NSError?
        guard FOSSDLLoad(sdlLibrary.path, &error) else {
            // Without SDL there is no UIApplication yet to show anything in.
            RuntimeLog.write("Can't load SDL3: \(error?.localizedDescription ?? "unknown error")", paths: nil)
            exit(EXIT_FAILURE)
        }
        let status = FOSSDLRunApp(CommandLine.argc, CommandLine.unsafeArgv) { _, _ in
            MainActor.assumeIsolated {
                Self.sdlMain()
            }
        }
        exit(status)
    }

    /// SDL's main callback, on the main thread with UIKit running: the launcher until the player starts the game.
    @MainActor
    private static func sdlMain() -> Never {
        guard let factories, let paths = try? GamePaths.standard() else {
            RuntimeLog.write("Can't create FactoriOS's folders in the app container", paths: nil)
            exit(EXIT_FAILURE)
        }
        let installation = GameInstallation(paths: paths)
        let coordinator = LaunchCoordinator()
        let window = RuntimeWindows.makeWindow()
        window.rootViewController = factories.launcher(installation, coordinator)
        window.makeKeyAndVisible()
        while true {
            let request = waitForLaunch(coordinator)
            let session = GameSession(paths: paths, launcherWindow: window, overlay: factories.overlay)
            do {
                try session.run(request)
            } catch {
                RuntimeLog.write("Can't start Factorio: \(error)", paths: paths)
                coordinator.fail(error.localizedDescription)
            }
        }
    }

    /// Runs the main run loop, which serves UIKit and the main actor, until the launcher asks to start the game.
    @MainActor
    private static func waitForLaunch(_ coordinator: LaunchCoordinator) -> LaunchRequest {
        while true {
            if let request = coordinator.takeRequest() {
                return request
            }
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: pumpInterval))
        }
    }
}
