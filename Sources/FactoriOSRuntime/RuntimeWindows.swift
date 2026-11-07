import FactoriOSCore
import Foundation
import UIKit

/// FactoriOS's own windows: the launcher's, the overlay above the game and the restart notice.
@MainActor
enum RuntimeWindows {
    /// The app's window scene, when UIKit has connected one (it does for apps with and without a scene manifest).
    static var windowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes.lazy.compactMap { $0 as? UIWindowScene }.first
    }

    /// The bounds of the screen the app is on.
    static var screenBounds: CGRect {
        windowScene?.screen.bounds ?? UIScreen.main.bounds
    }

    /// A new window on the app's scene, or covering the screen when there is no scene.
    static func makeWindow() -> UIWindow {
        if let windowScene {
            return UIWindow(windowScene: windowScene)
        }
        return UIWindow(frame: screenBounds)
    }

    /// A new full-screen overlay window one level above normal windows, where SDL's window is.
    static func makeOverlayWindow(root: UIViewController) -> PassthroughWindow {
        let window = windowScene.map { PassthroughWindow(windowScene: $0) } ?? PassthroughWindow(frame: screenBounds)
        window.frame = screenBounds
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
        window.backgroundColor = .clear
        window.rootViewController = root
        // Shown without becoming key: SDL's window keeps the keyboard focus for text input.
        window.isHidden = false
        return window
    }
}

/// A window whose empty areas let touches through to the windows below it.
final class PassthroughWindow: UIWindow {
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
