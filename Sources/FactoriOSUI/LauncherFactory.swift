public import FactoriOSCore
public import FactoriOSRuntime
import SwiftUI
public import UIKit

/// Builds FactoriOS's two screens for `AppEntry`: the launcher, and the overlay on the running game.
public enum LauncherFactory {
    /// The launcher: the instructions for installing the game from a Mac, then settings, saves and logs, and the
    /// buttons that start the game.
    ///
    /// - Parameters:
    ///   - paths: FactoriOS's folders in the app container.
    ///   - installation: Whether the game is installed, and which.
    ///   - coordinator: Starts the game when the player asks.
    /// - Returns: The launcher's root view controller, landscape only.
    @MainActor
    public static func makeLauncher(
        paths: GamePaths, installation: GameInstallation, coordinator: LaunchCoordinator
    ) -> UIViewController {
        let scene = LauncherScene(
            installation: installation,
            coordinator: coordinator,
            model: LauncherModel(paths: paths)
        )
        return LandscapeHostingController(rootView: scene)
    }

    /// The layer over the game: the on-screen controller and its toolbar, and touch gestures on the game.
    ///
    /// - Parameters:
    ///   - paths: FactoriOS's folders in the app container, where the controller layout is saved.
    ///   - input: Where the controls and gestures send their input.
    ///   - settings: The settings the game started with.
    /// - Returns: The overlay's view controller; its view is transparent and passes touches through except on the
    ///   controls and the toolbar.
    @MainActor
    public static func makeOverlay(paths: GamePaths, input: any GameInput, settings: GameSettings) -> UIViewController {
        OverlayViewController(input: input, settings: settings, layoutFile: paths.padLayoutFile, onFinishEditing: nil)
    }
}

/// A hosting controller that keeps the launcher in landscape, full screen.
final class LandscapeHostingController<Content: View>: UIHostingController<Content> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var prefersStatusBarHidden: Bool { true }
}
