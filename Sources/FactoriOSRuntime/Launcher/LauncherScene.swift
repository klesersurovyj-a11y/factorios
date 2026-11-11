import SwiftUI
import UIKit

/// The launcher's pages beyond Home.
enum LauncherPage: Hashable {
    /// Display, game and controller settings.
    case settings
    /// Importing and exporting saves.
    case saves
    /// FactoriOS's and Factorio's logs.
    case logs
}

/// The launcher: the instructions for installing the game until it is in, then Home and its pages.
struct LauncherScene: View {
    /// The installed game; `nil` until a device build has embedded it.
    let game: ImportedGame?
    /// Starts the game when the player asks.
    let coordinator: LaunchCoordinator
    /// The settings, saves and logs the pages show.
    let model: LauncherModel

    var body: some View {
        NavigationStack {
            stageView()
                .navigationDestination(for: LauncherPage.self) { page in
                    destination(page)
                }
                .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .tint(.orange)
    }

    /// Welcome before the game is installed, Home once it is.
    @ViewBuilder
    private func stageView() -> some View {
        if let game {
            HomeView(game: game, coordinator: coordinator, model: model)
        } else {
            WelcomeView()
        }
    }

    /// The screen for `page`.
    @ViewBuilder
    private func destination(_ page: LauncherPage) -> some View {
        switch page {
        case .settings:
            SettingsView(model: model)
        case .saves:
            SavesView(model: model)
        case .logs:
            LogsView(paths: model.paths, settings: model.settings)
        }
    }
}

/// A hosting controller that keeps the launcher in landscape, full screen.
final class LandscapeHostingController<Content: View>: UIHostingController<Content> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var prefersStatusBarHidden: Bool { true }
}
