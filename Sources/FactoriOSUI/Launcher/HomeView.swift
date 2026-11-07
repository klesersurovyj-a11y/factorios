import FactoriOSCore
import FactoriOSRuntime
import SwiftUI

/// The launcher's main screen: Continue the newest save or open Factorio's main menu, and the way to the rest.
struct HomeView: View {
    let game: ImportedGame
    let installation: GameInstallation
    let coordinator: LaunchCoordinator
    let model: LauncherModel

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .center, spacing: 40) {
            playColumn
                .frame(maxWidth: 380, alignment: .leading)
            pagesColumn
                .frame(maxWidth: 300)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { model.refreshSaves() }
    }

    private var playColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("FactoriOS")
                .font(.largeTitle.bold())
            Text(versionText)
                .foregroundStyle(.secondary)
            Spacer().frame(height: 8)
            playButtons
            if let error = coordinator.launchError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            if !installation.hasSigningIdentity {
                Label("No Apple Development identity: import it again in Settings.", systemImage: "checkmark.seal")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var pagesColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            pageLink("Settings", systemImage: "gearshape", page: .settings)
            pageLink("Saves", systemImage: "externaldrive", page: .saves)
            pageLink("Logs", systemImage: "doc.text.magnifyingglass", page: .logs)
            Button {
                if let url = model.filesURL {
                    openURL(url)
                }
            } label: {
                Label("Factorio folder in Files", systemImage: "folder")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var versionText: String {
        game.isDemo ? "Factorio \(game.version) (demo)" : "Factorio \(game.version)"
    }

    @ViewBuilder
    private var playButtons: some View {
        if let save = model.newestSave {
            Button {
                coordinator.launch(.continueSave(path: save.url.path))
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Continue", systemImage: "play.fill")
                        .font(.title3.bold())
                    Text("\(save.name) · \(save.modified, format: .relative(presentation: .named))")
                        .font(.footnote)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        Button {
            coordinator.launch(.mainMenu)
        } label: {
            Label("Main menu", systemImage: "house")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func pageLink(_ title: String, systemImage: String, page: LauncherPage) -> some View {
        NavigationLink(value: page) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}
