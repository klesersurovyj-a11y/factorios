import FactoriOSCore
import SwiftUI

/// The display, game and controller settings, and the game's files.
struct SettingsView: View {
    @Bindable var model: LauncherModel

    @State private var editingLayout = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            if let error = model.settingsError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            displaySection
            gameSection
            controllerSection
            filesSection
        }
        .navigationTitle("Settings")
        .fullScreenCover(isPresented: $editingLayout) {
            PadLayoutEditorScreen(settings: model.settings, layoutFile: model.paths.padLayoutFile) {
                editingLayout = false
            }
            .ignoresSafeArea()
        }
    }

    private var displaySection: some View {
        Section {
            Picker("Frame rate", selection: $model.settings.frameRate) {
                Text("30 FPS").tag(GameSettings.FrameRate.thirty)
                Text("60 FPS").tag(GameSettings.FrameRate.sixty)
            }
            Picker("Frame", selection: $model.settings.frame) {
                Text("Off").tag(GameSettings.Frame.off)
                Text("Thin").tag(GameSettings.Frame.thin)
                Text("Wide").tag(GameSettings.Frame.wide)
            }
            Picker("UI size", selection: $model.settings.uiScale) {
                Text("Large").tag(GameSettings.UIScale.large)
                Text("Medium").tag(GameSettings.UIScale.medium)
                Text("Small").tag(GameSettings.UIScale.small)
            }
            Picker("Sprite quality", selection: $model.settings.spriteQuality) {
                Text("High").tag(GameSettings.SpriteQuality.high)
                Text("Medium").tag(GameSettings.SpriteQuality.medium)
            }
            Toggle("Light graphics", isOn: $model.settings.lightGraphics)
        } header: {
            Text("Display")
        } footer: {
            Text(
                """
                These apply the next time Factorio starts. The frame keeps rounded screen corners off the game's \
                menus. UI size is Factorio's UI scale, as on a 720-, 900- or 1080-pixel monitor: Large is the \
                smallest screen Factorio supports, Small fits the most game; Factorio's own UI scale setting lasts \
                until the next start. High sprites need more memory than an iPhone gives an app, and iOS closes \
                Factorio while it loads them; Medium sprites take a quarter of that. Light graphics turn off smoke, \
                clouds, decoratives, particles, shadows and terrain effects; turning them off again puts the effects \
                back.
                """
            )
        }
    }

    private var gameSection: some View {
        Section {
            Toggle("FPS counter", isOn: $model.settings.fpsCounter)
            Toggle("Detailed logs", isOn: $model.settings.detailedLogs)
            Toggle("Vibration", isOn: $model.settings.vibration)
        } header: {
            Text("Game")
        } footer: {
            Text(
                """
                The FPS counter and detailed logs apply the next time Factorio starts. Detailed logs turn on \
                Metal's validation, which reports every graphics error, and SDL's verbose logging: turn them on to \
                report a problem, play until it shows, then copy the Logs.
                """
            )
        }
    }

    private var controllerSection: some View {
        Section {
            Button {
                editingLayout = true
            } label: {
                Label("Edit controller layout", systemImage: "slider.horizontal.3")
            }
        } header: {
            Text("Controller")
        } footer: {
            Text(
                """
                Move, resize, remove and add the on-screen buttons. In a game, the toolbar at the top does the \
                same. The buttons step aside while a controller is connected.
                """
            )
        }
    }

    private var filesSection: some View {
        Section {
            Button {
                if let url = model.filesURL {
                    openURL(url)
                }
            } label: {
                Label("Open the Factorio folder in Files", systemImage: "folder")
            }
        } header: {
            Text("Files")
        } footer: {
            Text(
                """
                The Factorio folder holds your saves, mods, config and scenarios; mod changes apply the next time \
                the game starts. To update Factorio, run `mise run deploy` again from the Mac.
                """
            )
        }
    }
}
