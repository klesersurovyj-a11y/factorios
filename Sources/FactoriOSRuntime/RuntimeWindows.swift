import FactoriOSCore
import Foundation
import UIKit

/// FactoriOS's own windows: the launcher's, the overlay above the game and the restart notice.
@MainActor
enum RuntimeWindows {
    /// The app's window scene.
    ///
    /// Info.plist declares SDL's scene delegate, and SDL calls FactoriOS's main only once the scene has connected, so
    /// it exists for everything FactoriOS shows.
    static var windowScene: UIWindowScene {
        guard let scene = UIApplication.shared.connectedScenes.lazy.compactMap({ $0 as? UIWindowScene }).first else {
            // Only reachable if Info.plist lost its scene manifest or SDL called main before the scene connected.
            fatalError("FactoriOS runs before UIKit has connected its window scene")
        }
        return scene
    }

    /// A new window on the app's scene.
    static func makeWindow() -> UIWindow {
        UIWindow(windowScene: windowScene)
    }

    /// A new full-screen overlay window one level above normal windows, where SDL's window is.
    static func makeOverlayWindow(root: UIViewController) -> PassthroughWindow {
        let scene = windowScene
        let window = PassthroughWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
        window.backgroundColor = .clear
        window.rootViewController = root
        // Shown without becoming key, and never key (see PassthroughWindow): SDL's window keeps the keyboard focus.
        window.isHidden = false
        return window
    }
}

/// A window whose empty areas let touches through to the windows below it.
///
/// It never becomes key: UIKit makes a touched window key, and SDL's window losing the key status loses SDL's
/// keyboard focus, which drops text input and keyboard events.
final class PassthroughWindow: UIWindow {
    override var canBecomeKey: Bool { false }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === self || view === rootViewController?.view ? nil : view
    }
}

/// Tells the player the game asked to restart, which iOS can't do, and quits when they close the notice.
@MainActor
enum RestartPrompt {
    /// Shows the notice above everything and runs the main run loop until the player closes it; then exits.
    static func show(arguments: [String], paths: GamePaths) -> Never {
        RuntimeLog.write("Factorio asked to restart with \(arguments)", paths: paths)
        let window = RuntimeWindows.makeWindow()
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        let alert = UIAlertController(
            title: "Factorio needs to restart",
            message: "Reopen FactoriOS to continue.",
            preferredStyle: .alert
        )
        alert.addAction(
            UIAlertAction(title: "Close", style: .default) { _ in
                exit(EXIT_SUCCESS)
            }
        )
        host.present(alert, animated: true)
        // The game called execv from its main loop and is waiting for it; only UIKit runs until Close.
        while true {
            _ = RunLoop.main.run(mode: .default, before: .distantFuture)
        }
    }
}
