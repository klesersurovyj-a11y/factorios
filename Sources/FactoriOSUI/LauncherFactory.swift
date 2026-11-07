public import FactoriOSCore
public import FactoriOSRuntime
import SwiftUI
public import UIKit

/// Builds FactoriOS's two screens for `AppEntry`: the launcher, and the overlay on the running game.
public enum LauncherFactory {
    /// The launcher: importing the game and the certificate, settings, saves and logs, and the buttons that start
    /// the game.
    ///
    /// - Parameters:
    ///   - installation: The imported game and its import's progress.
    ///   - coordinator: Starts the game when the player asks.
    /// - Returns: The launcher's root view controller, landscape only.
    @MainActor
    public static func makeLauncher(
        installation: GameInstallation, coordinator: LaunchCoordinator
    ) -> UIViewController {
        let scene: LauncherScene
        do {
            let model = LauncherModel(paths: try GamePaths.standard())
            scene = LauncherScene(installation: installation, coordinator: coordinator, model: model, failure: nil)
        } catch {
            scene = LauncherScene(
                installation: installation,
                coordinator: coordinator,
                model: nil,
                failure: error.localizedDescription
            )
        }
        return LandscapeHostingController(rootView: scene)
    }

    /// The layer over the game: the on-screen controller and its toolbar, and touch gestures on the game.
    ///
    /// - Parameters:
    ///   - input: Where the controls and gestures send their input.
    ///   - settings: The settings the game started with.
    /// - Returns: The overlay's view controller; its view is transparent and passes touches through except on the
    ///   controls and the toolbar.
    @MainActor
    public static func makeOverlay(input: any GameInput, settings: GameSettings) -> UIViewController {
        // Without a container directory the layout can't be saved; the default one still works for this session.
        let layoutFile = try? GamePaths.standard().padLayoutFile
        return OverlayViewController(input: input, settings: settings, layoutFile: layoutFile, onFinishEditing: nil)
    }
}

/// A hosting controller that keeps the launcher in landscape, full screen.
final class LandscapeHostingController<Content: View>: UIHostingController<Content> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var prefersStatusBarHidden: Bool { true }
}
