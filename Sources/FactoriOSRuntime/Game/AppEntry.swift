import Darwin
import FactoriOSCompat
import FactoriOSCore
import Foundation
import SwiftUI
import UIKit

/// The app's entry point.
///
/// SDL has to own the application's start-up on iOS, so FactoriOS hands it over at once and everything happens inside
/// SDL's main callback.
@main
enum AppEntry {
    /// How long one turn of the launcher's run-loop pump waits for events.
    private static let pumpInterval: TimeInterval = 0.05

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
    @MainActor
static func main() {
    var error: NSError?
    guard FOSSDLLoad(sdlLibrary.path, &error) else {
        RuntimeLog.write("Can't load SDL3: \(error?.localizedDescription ?? "unknown error")", paths: nil)
        exit(EXIT_FAILURE)
    }

    let status = FOSSDLRunApp(CommandLine.argc, CommandLine.unsafeArgv) { _, _ in
        MainActor.assumeIsolated {
            Self.sdlMain()
        }
        return 0
    }
    exit(status)
}

    /// SDL's main callback, on the main thread with UIKit running: the launcher until the player starts the game.
    @MainActor
    private static func sdlMain() -> Never {
        guard let paths = try? GamePaths.standard() else {
            RuntimeLog.write("Can't create FactoriOS's folders in the app container", paths: nil)
            exit(EXIT_FAILURE)
        }
        // The game a device build embedded in the app bundle, with the facts `deploy` recorded about it.
        let game = GameLibrary.isBundled(paths: paths) ? ImportedGame.installed(paths: paths) : nil
        let coordinator = LaunchCoordinator()
        let window = UIWindow(windowScene: RuntimeWindows.windowScene)
        window.rootViewController = LandscapeHostingController(
            rootView: LauncherScene(game: game, coordinator: coordinator, model: LauncherModel(paths: paths))
        )
        window.makeKeyAndVisible()
        while true {
            let request = waitForLaunch(coordinator)
            let session = GameSession(paths: paths, launcherWindow: window)
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
