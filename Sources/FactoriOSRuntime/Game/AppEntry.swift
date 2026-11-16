import Darwin
import FactoriOSCompat
import FactoriOSCore
import Foundation
import SwiftUI
import UIKit

@main
enum AppEntry {
    private static let pumpInterval: TimeInterval = 0.05

    static var sdlLibrary: URL {
        let frameworks = Bundle.main.privateFrameworksURL ?? Bundle.main.bundleURL.appendingPathComponent("Frameworks")
        return frameworks.appendingPathComponent("SDL3.framework/SDL3")
    }

    @MainActor
    static func main() {
        var error: NSError?
        guard FOSSDLLoad(sdlLibrary.path, &error) else {
            RuntimeLog.write("Can't load SDL3: \(error?.localizedDescription ?? "unknown error")", paths: nil)
            exit(EXIT_FAILURE)
        }

        let status = FOSSDLRunApp(CommandLine.argc, CommandLine.unsafeArgv) { _, _ in
            Self.sdlMain()
            return 0
        }
        exit(status)
    }

    @MainActor
    private static func sdlMain() -> Never {
        guard let paths = try? GamePaths.standard() else {
            RuntimeLog.write("Can't create FactoriOS's folders in the app container", paths: nil)
            exit(EXIT_FAILURE)
        }
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
