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

/// The launcher: the welcome and import screens until the game is in, then Home and its pages.
struct LauncherScene: View {
    let installation: GameInstallation
    let coordinator: LaunchCoordinator
    let model: LauncherModel?
    /// Why the app's folders couldn't be found, if they couldn't.
    let failure: String?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    stageView(model)
                        .navigationDestination(for: LauncherPage.self) { page in
                            destination(page, model: model)
                        }
                } else {
                    ContentUnavailableView(
                        "FactoriOS can't start",
                        systemImage: "exclamationmark.triangle",
                        description: Text(failure ?? "The app's folders couldn't be opened.")
                    )
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .tint(.orange)
    }

    @ViewBuilder
    private func stageView(_ model: LauncherModel) -> some View {
        switch installation.stage {
        case .notInstalled:
            WelcomeView()
        case .ready(let game):
            HomeView(game: game, coordinator: coordinator, model: model)
        }
    }

    @ViewBuilder
    private func destination(_ page: LauncherPage, model: LauncherModel) -> some View {
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
