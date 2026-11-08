import FactoriOSCore
import FactoriOSRuntime
import SwiftUI

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
    /// Whether the game is installed, and which.
    let installation: GameInstallation
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
        switch installation.stage {
        case .notInstalled:
            WelcomeView()
        case .ready(let game):
            HomeView(game: game, coordinator: coordinator, model: model)
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
